import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show Uint8List;
import 'dart:ui';

import 'package:camera/camera.dart' show ImageFormatGroup;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_capture_diagnostics.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_enrollment_service.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';

/// Runs the face-enrollment capture pipeline (decode → pixel quality →
/// liveness → alignment → MobileFaceNet embedding → identity/outlier
/// logic → the [FaceEnrollmentService] phase state machine, including
/// [FaceEnrollmentService.finalizeEnrollment]) on one dedicated, long-lived
/// worker isolate, so none of it blocks `FaceEnrollmentScreen`'s UI isolate
/// (setState/animations/the camera preview overlay).
///
/// This is the main-isolate-side handle: [FaceEnrollmentScreen] owns one
/// instance for the life of a capture session, feeding it sampled camera
/// frames via [submitFrame] (a "latest wins," depth-1 mailbox — mirrors the
/// screen's own single-flight frame guard, just across the isolate
/// boundary: a frame submitted while the worker is still busy with a
/// previous one replaces it rather than queuing) and listening to [updates]
/// for state to render. Detection itself (`FaceDetectionService`, an ML
/// Kit platform-channel object) deliberately stays on the caller's isolate
/// — see [submitFrame]'s parameters, which take already-detected
/// [DetectedFace]s rather than a raw frame to detect.
///
/// Never sends a raw camera frame or an embedding vector to a log/print
/// call anywhere in this file or [_workerMain] — matching the invariant
/// documented on [FaceEnrollmentService].
class FaceEnrollmentWorker {
  FaceEnrollmentWorker._(
    this._isolate,
    this._toWorker,
    this._fromWorker,
    this._updatesController,
    this._shutdownAck,
  );

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final StreamController<FaceEnrollmentUpdate> _updatesController;
  final Completer<void> _shutdownAck;

  /// Per-frame state to render, plus (debug-only) diagnostics and (once,
  /// on the update where scanning completes) the final enrollment result.
  Stream<FaceEnrollmentUpdate> get updates => _updatesController.stream;

  /// Spawns the worker isolate and completes once it has loaded the
  /// embedding interpreter and is ready to accept frames.
  ///
  /// [interpreterAddress] is the *already-loaded* main-isolate
  /// `Interpreter`'s native address (`FaceEmbeddingService.address`) —
  /// loading the model itself (`Interpreter.fromAsset`) depends on
  /// Flutter's asset bundle, so it must happen on an isolate with Flutter
  /// bindings before spawning; only the address crosses over, and the
  /// worker attaches to it via `IsolateInterpreter.create`.
  ///
  /// [templateRepository] is read here (via
  /// [FaceTemplateRepository.exportForIsolateTransfer]) to reconstruct an
  /// equivalent repository inside the worker — the instance itself can't
  /// cross an isolate boundary (see that method's doc comment) — so
  /// [FaceEnrollmentService.finalizeEnrollment]'s duplicate-check can run
  /// where the accepted samples already live, without ever sending a raw
  /// embedding across in the meantime.
  static Future<FaceEnrollmentWorker> spawn({
    required int interpreterAddress,
    required String operatorId,
    required FaceTemplateRepository templateRepository,
    int requiredSamples = 6,
    int minSurvivingSamples = 5,
  }) async {
    final transfer = await templateRepository.exportForIsolateTransfer();

    final fromWorker = ReceivePort();
    final readyCompleter = Completer<SendPort>();
    final updatesController = StreamController<FaceEnrollmentUpdate>.broadcast();
    final shutdownAck = Completer<void>();

    fromWorker.listen((message) {
      if (message is SendPort) {
        readyCompleter.complete(message);
      } else if (message is FaceEnrollmentUpdate) {
        updatesController.add(message);
      } else if (message is _WorkerShutdownAck) {
        if (!shutdownAck.isCompleted) shutdownAck.complete();
      }
    });

    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerBootstrap(
        mainSendPort: fromWorker.sendPort,
        interpreterAddress: interpreterAddress,
        operatorId: operatorId,
        directoryPath: transfer.directoryPath,
        keyBytes: transfer.keyBytes,
        requiredSamples: requiredSamples,
        minSurvivingSamples: minSurvivingSamples,
      ),
      debugName: 'FaceEnrollmentWorker',
    );

    final toWorker = await readyCompleter.future;
    return FaceEnrollmentWorker._(
      isolate,
      toWorker,
      fromWorker,
      updatesController,
      shutdownAck,
    );
  }

  /// Submits one already-detected frame for processing. "Latest wins": if
  /// the worker is still busy with a previously-submitted frame, this one
  /// simply replaces whatever was queued behind it — never blocks, never
  /// builds up a backlog.
  ///
  /// [bytes]/[bytesPerRow]/[width]/[height]/[formatGroup] are the raw
  /// first-plane fields of the originating `CameraImage` (which itself
  /// can't cross an isolate boundary — see
  /// `CameraFrameConverter.decodePlane`'s doc comment); decoding is
  /// deferred until the worker actually needs the pixels, so a frame this
  /// call ends up dropping (superseded before it's processed) never pays
  /// the decode cost at all.
  void submitFrame({
    required Uint8List bytes,
    required int bytesPerRow,
    required int width,
    required int height,
    required ImageFormatGroup formatGroup,
    required int rotationDegrees,
    required List<DetectedFace> faces,
    required Size imageSize,
  }) {
    _toWorker.send(
      _FrameJob(
        bytes: bytes,
        bytesPerRow: bytesPerRow,
        width: width,
        height: height,
        formatGroup: formatGroup,
        rotationDegrees: rotationDegrees,
        faces: faces,
        imageSize: imageSize,
      ),
    );
  }

  /// Clears any in-flight enrollment progress and returns the worker's
  /// phase state machine to its initial (stabilizing) phase — the
  /// isolate-boundary equivalent of `FaceEnrollmentService.reset`, used on
  /// cancel/retry.
  void reset() => _toWorker.send(_WorkerCommand.reset);

  /// Shuts the worker isolate down: closes its `IsolateInterpreter` (which
  /// owns its own nested isolate — see `IsolateInterpreter.close`) and
  /// waits for that to finish *before* returning, so the caller only needs
  /// to close its own main-isolate `Interpreter`
  /// (`FaceEmbeddingService.close`) after this completes — never before,
  /// or the worker's interpreter isolate could still be touching the
  /// now-deleted native interpreter.
  Future<void> dispose() async {
    _toWorker.send(_WorkerCommand.shutdown);
    await _shutdownAck.future;
    _isolate.kill();
    _fromWorker.close();
    await _updatesController.close();
  }
}

/// One update from the worker, per processed frame.
///
/// [diagnostics] is only ever non-null in debug builds, and only on the
/// (throttled) frames where it was actually recomputed — a null value
/// means "no change," not "no face"; the caller should keep showing
/// whatever it last rendered (matches
/// `FrameQualityAnalyzer`/`FaceEnrollmentService`'s own pixel-check
/// throttle, which this mirrors independently for the debug HUD).
///
/// [result] is non-null exactly once per session: on the update
/// immediately following [state] reporting
/// [FaceEnrollmentStatus.processing], once
/// [FaceEnrollmentService.finalizeEnrollment] resolves. It is sent as a
/// *second*, separate update (with [state] repeated and [diagnostics]
/// null) rather than bundled into the first `processing` update, so the
/// caller still sees an immediate "Processing…" render before the
/// (async, potentially-not-instant) finalize result arrives — the same
/// two-step timing the pre-isolate implementation had between
/// `evaluateAndCapture` returning and `finalizeEnrollment` resolving.
class FaceEnrollmentUpdate {
  const FaceEnrollmentUpdate({required this.state, this.diagnostics, this.result});

  final FaceEnrollmentState state;
  final FaceCaptureDiagnostics? diagnostics;
  final FaceEnrollmentResult? result;
}

// ─────────────────────────── isolate-boundary messages ───────────────────

/// The single argument [Isolate.spawn] hands to [_workerMain].
class _WorkerBootstrap {
  const _WorkerBootstrap({
    required this.mainSendPort,
    required this.interpreterAddress,
    required this.operatorId,
    required this.directoryPath,
    required this.keyBytes,
    required this.requiredSamples,
    required this.minSurvivingSamples,
  });

  final SendPort mainSendPort;
  final int interpreterAddress;
  final String operatorId;
  final String directoryPath;
  final List<int> keyBytes;
  final int requiredSamples;
  final int minSurvivingSamples;
}

/// One sampled, already-detected camera frame, main isolate → worker.
class _FrameJob {
  const _FrameJob({
    required this.bytes,
    required this.bytesPerRow,
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.rotationDegrees,
    required this.faces,
    required this.imageSize,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int width;
  final int height;
  final ImageFormatGroup formatGroup;
  final int rotationDegrees;
  final List<DetectedFace> faces;
  final Size imageSize;
}

enum _WorkerCommand { reset, shutdown }

class _WorkerShutdownAck {
  const _WorkerShutdownAck();
}

/// Same throttle interval as the pre-isolate implementation's
/// `_lastDiagnosticsAt` — see [FaceEnrollmentUpdate.diagnostics].
const Duration _diagnosticsInterval = Duration(milliseconds: 200);

// ────────────────────────────── worker isolate ────────────────────────────

Future<void> _workerMain(_WorkerBootstrap bootstrap) async {
  final isolateInterpreter = await IsolateInterpreter.create(
    address: bootstrap.interpreterAddress,
    debugName: 'FaceEnrollmentEmbeddingIsolate',
  );
  final embeddingService = FaceEmbeddingService.fromIsolateInterpreter(
    isolateInterpreter,
  );
  final templateRepository = FaceTemplateRepository(
    baseDirectory: Directory(bootstrap.directoryPath),
    key: SecretKey(bootstrap.keyBytes),
  );
  final enrollmentService = FaceEnrollmentService(
    embeddingService: embeddingService,
    templateRepository: templateRepository,
    requiredSamples: bootstrap.requiredSamples,
    minSurvivingSamples: bootstrap.minSurvivingSamples,
  );

  DateTime? lastDiagnosticsAt;

  img.Image decode(_FrameJob job) => CameraFrameConverter.decodePlane(
    bytes: job.bytes,
    bytesPerRow: job.bytesPerRow,
    width: job.width,
    height: job.height,
    formatGroup: job.formatGroup,
  );

  Future<void> handleJob(_FrameJob job) async {
    final now = DateTime.now();
    final dueForDiagnostics =
        kDebugMode &&
        job.faces.length == 1 &&
        (lastDiagnosticsAt == null ||
            now.difference(lastDiagnosticsAt!) >= _diagnosticsInterval);

    img.Image? precomputedFrame;
    if (dueForDiagnostics) {
      precomputedFrame = decode(job);
      lastDiagnosticsAt = now;
    }

    final state = await enrollmentService.evaluateAndCapture(
      frameProvider: () => precomputedFrame ?? decode(job),
      faces: job.faces,
      imageSize: job.imageSize,
      rotationDegrees: job.rotationDegrees,
    );

    FaceCaptureDiagnostics? diagnostics;
    if (kDebugMode) {
      if (precomputedFrame != null) {
        diagnostics = _buildDiagnostics(
          job.faces.single,
          job.imageSize,
          job.rotationDegrees,
          precomputedFrame,
          enrollmentService,
          state,
        );
      } else if (job.faces.length != 1) {
        diagnostics = FaceCaptureDiagnostics(faceCount: job.faces.length);
      }
    }

    if (state.status == FaceEnrollmentStatus.processing) {
      bootstrap.mainSendPort.send(
        FaceEnrollmentUpdate(state: state, diagnostics: diagnostics),
      );
      final result = await enrollmentService.finalizeEnrollment(
        operatorId: bootstrap.operatorId,
      );
      bootstrap.mainSendPort.send(
        FaceEnrollmentUpdate(state: state, result: result),
      );
      return;
    }

    bootstrap.mainSendPort.send(
      FaceEnrollmentUpdate(state: state, diagnostics: diagnostics),
    );
  }

  _FrameJob? pending;
  var busy = false;

  void maybeProcessNext() {
    if (busy) return;
    final job = pending;
    if (job == null) return;
    pending = null;
    busy = true;
    unawaited(
      handleJob(job).whenComplete(() {
        busy = false;
        maybeProcessNext();
      }),
    );
  }

  final commandPort = ReceivePort();
  bootstrap.mainSendPort.send(commandPort.sendPort);

  await for (final message in commandPort) {
    if (message is _FrameJob) {
      pending = message;
      maybeProcessNext();
    } else if (message == _WorkerCommand.reset) {
      pending = null;
      enrollmentService.reset();
    } else if (message == _WorkerCommand.shutdown) {
      await isolateInterpreter.close();
      bootstrap.mainSendPort.send(const _WorkerShutdownAck());
      commandPort.close();
    }
  }
}

/// Relocated, unchanged, from the pre-isolate `FaceEnrollmentScreen`
/// implementation — see [FaceEnrollmentUpdate.diagnostics] for why this
/// still independently re-derives the ML-Kit-quality-gate breakdown
/// (`FaceDetectionService.evaluateQuality`) rather than threading it
/// through from [FaceEnrollmentService.evaluateAndCapture]'s own internal
/// call: it's a pure function of the same inputs, so the two can never
/// disagree, and this keeps `FaceEnrollmentService` from needing to expose
/// its intermediate quality result just for a debug HUD.
FaceCaptureDiagnostics _buildDiagnostics(
  DetectedFace face,
  Size imageSize,
  int rotationDegrees,
  img.Image frame,
  FaceEnrollmentService enrollmentService,
  FaceEnrollmentState state,
) {
  final quality = FaceDetectionService.evaluateQuality(
    [face],
    imageSize,
    rotationDegrees: rotationDegrees,
  );
  final pixel = FrameQualityAnalyzer.diagnose(frame, face.boundingBox);
  final readyForCapture =
      quality.sizePassed &&
      quality.centerPassed &&
      quality.posePassed &&
      quality.eyesPassed &&
      pixel.brightnessPassed &&
      pixel.sharpnessPassed;
  final failedReason = !quality.passed
      ? quality.primaryMessage
      : (!pixel.brightnessPassed
            ? FaceQualityIssue.poorLighting.guidance
            : (!pixel.sharpnessPassed ? FaceQualityIssue.tooBlurry.guidance : null));

  return FaceCaptureDiagnostics(
    faceCount: 1,
    yawDegrees: face.headEulerAngleY,
    pitchDegrees: face.headEulerAngleX,
    faceWidthFraction: quality.widthFraction,
    centerOffsetFraction: quality.centerOffsetFraction,
    brightness: pixel.brightness,
    sharpness: pixel.sharpness,
    sizePassed: quality.sizePassed,
    centerPassed: quality.centerPassed,
    posePassed: quality.posePassed,
    eyesPassed: quality.eyesPassed,
    brightnessPassed: pixel.brightnessPassed,
    sharpnessPassed: pixel.sharpnessPassed,
    stableProgress: enrollmentService.stableProgress,
    scanning: enrollmentService.isScanning,
    scanProgress: enrollmentService.isScanning ? state.scanProgress : null,
    identityLocked: enrollmentService.identityLocked,
    samplesAccepted: enrollmentService.samplesCaptured,
    readyForCapture: readyForCapture,
    failedReason: failedReason,
  );
}
