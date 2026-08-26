import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/repositories/authentication_log_repository.dart';
import 'package:rev_crane_control_ops/services/secure_key_provider.dart';

const String _kAuthLogKeyDomain = 'intellihmi.auth-log.key';

const String _kPrefMaxAgeDays = 'auth_log_retention_max_age_days';
const String _kPrefMaxRecords = 'auth_log_retention_max_records';
const String _kPrefMaxFileSizeBytes = 'auth_log_retention_max_file_size_bytes';

const int _defaultMaxAgeDays = 180;
const int _defaultMaxRecords = 5000;
const int _defaultMaxFileSizeBytes = 5 * 1024 * 1024;

/// Narrow interface [CraneController] depends on, so it never touches the
/// filesystem, crypto, or `flutter_secure_storage` directly — only this one
/// injected object — and so tests can supply a fake that never completes,
/// to prove authentication never waits on a log write.
abstract interface class AuditLogger {
  Future<void> record({
    required AuthEventResult result,
    required AuthEventMethod method,
    String? userIdentifier,
    String? operatorId,
    String? operatorNameSnapshot,
    String? role,
    String? deviceId,
    String? plcDeviceName,
    String? plcDeviceId,
    String? plcType,
    String? connectionStatus,
    String? sessionCorrelationId,
    String? failureReason,
    String? detailCode,
  });

  Future<void> recordOperatorEvent({
    required OperatorLifecycleEvent event,
    required String operatorId,
    required String operatorNameSnapshot,
    required String role,
  });
}

/// Business logic on top of [AuthenticationLogRepository]: retention/size
/// bounds, crash-truncation healing, and a serialized write queue so every
/// call site can fire-and-forget without racing its own writes.
///
/// Every mutating call (`record`, `recordOperatorEvent`, the startup
/// compaction in [ensureLoaded]) is chained onto the same private future so
/// records land in the file in the order they were logged and never
/// interleave — but none of it is ever awaited by callers on the hot path.
class AuthAuditLogService implements AuditLogger {
  AuthAuditLogService({AuthenticationLogRepository? repository})
    : _repository = repository;

  AuthenticationLogRepository? _repository;
  Future<void> _writeQueue = Future.value();
  bool _loaded = false;

  int _maxAgeDays = _defaultMaxAgeDays;
  int _maxRecords = _defaultMaxRecords;
  int _maxFileSizeBytes = _defaultMaxFileSizeBytes;

  Future<AuthenticationLogRepository> _repo() async {
    final existing = _repository;
    if (existing != null) return existing;

    final directory = await getApplicationSupportDirectory();
    final key = await SecureKeyProvider.getOrCreateKey(_kAuthLogKeyDomain);
    final created = AuthenticationLogRepository(
      baseDirectory: directory,
      key: key,
    );
    _repository = created;
    return created;
  }

  /// Loads the retention policy and runs one startup compaction pass.
  /// Idempotent and safe to call from multiple places — only the first
  /// call does any work.
  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    _loaded = true;
    return _enqueue((repo) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        _maxAgeDays = prefs.getInt(_kPrefMaxAgeDays) ?? _defaultMaxAgeDays;
        _maxRecords = prefs.getInt(_kPrefMaxRecords) ?? _defaultMaxRecords;
        _maxFileSizeBytes =
            prefs.getInt(_kPrefMaxFileSizeBytes) ?? _defaultMaxFileSizeBytes;
      } catch (_) {
        // Keep the hardcoded defaults if preferences can't be read.
      }
      await _compactIfNeeded(repo);
    });
  }

  @override
  Future<void> record({
    required AuthEventResult result,
    required AuthEventMethod method,
    String? userIdentifier,
    String? operatorId,
    String? operatorNameSnapshot,
    String? role,
    String? deviceId,
    String? plcDeviceName,
    String? plcDeviceId,
    String? plcType,
    String? connectionStatus,
    String? sessionCorrelationId,
    String? failureReason,
    String? detailCode,
  }) {
    final entry = AuthLogEntry(
      timestamp: DateTime.now(),
      category: AuthLogCategory.authentication,
      result: result,
      method: method,
      userIdentifier: userIdentifier,
      operatorId: operatorId,
      operatorNameSnapshot: operatorNameSnapshot,
      role: role,
      deviceId: deviceId,
      plcDeviceName: plcDeviceName,
      plcDeviceId: plcDeviceId,
      plcType: plcType,
      connectionStatus: connectionStatus,
      sessionCorrelationId: sessionCorrelationId,
      failureReason: failureReason,
      detailCode: detailCode,
    );
    return _append(entry);
  }

  @override
  Future<void> recordOperatorEvent({
    required OperatorLifecycleEvent event,
    required String operatorId,
    required String operatorNameSnapshot,
    required String role,
  }) {
    final entry = AuthLogEntry(
      timestamp: DateTime.now(),
      category: AuthLogCategory.operatorManagement,
      lifecycleEvent: event,
      operatorId: operatorId,
      operatorNameSnapshot: operatorNameSnapshot,
      role: role,
    );
    return _append(entry);
  }

  Future<void> _append(AuthLogEntry entry) {
    return _enqueue((repo) async {
      await repo.append(entry);
      await _compactIfNeeded(repo);
    });
  }

  /// Chains [action] onto the private write queue and swallows any error
  /// inside it — a disk-full or IO failure must never throw back into the
  /// BLE/auth call stack that (indirectly, via [AuditLogger]) triggered it.
  Future<void> _enqueue(
    Future<void> Function(AuthenticationLogRepository repo) action,
  ) {
    final next = _writeQueue.then((_) async {
      try {
        final repo = await _repo();
        await action(repo);
      } catch (_) {
        // Best-effort logging only; never propagate.
      }
    });
    _writeQueue = next;
    return next;
  }

  Future<void> _compactIfNeeded(AuthenticationLogRepository repo) async {
    final result = await repo.readAll();
    var entries = result.entries;
    var needsRewrite = false;

    if (result.truncated) {
      // Make the recovery itself visible instead of silently dropping the
      // unreadable tail — a crash-truncated write and a tampering attempt
      // should both leave a trace, not disappear.
      entries = [
        ...entries,
        AuthLogEntry(
          timestamp: DateTime.now(),
          category: AuthLogCategory.system,
          detailCode: 'log_integrity_recovered',
          failureReason: 'Trailing unreadable audit record discarded.',
        ),
      ];
      needsRewrite = true;
    }

    final cutoff = DateTime.now().subtract(Duration(days: _maxAgeDays));
    final beforeAgeFilter = entries.length;
    entries = entries.where((e) => e.timestamp.isAfter(cutoff)).toList();
    if (entries.length != beforeAgeFilter) needsRewrite = true;

    if (entries.length > _maxRecords) {
      entries = entries.sublist(entries.length - _maxRecords);
      needsRewrite = true;
    }

    if (!needsRewrite) {
      final size = await repo.sizeBytes();
      if (size > _maxFileSizeBytes && entries.isNotEmpty) {
        // Bounded by size alone (e.g. unusually large records) — trim the
        // oldest 20% and let the next pass re-check.
        final target = (entries.length * 0.8).floor().clamp(
          1,
          entries.length,
        );
        entries = entries.sublist(entries.length - target);
        needsRewrite = true;
      }
    }

    if (needsRewrite) {
      await repo.rewrite(entries);
    }
  }

  Future<List<AuthLogEntry>> getEntries({
    AuthLogCategory? category,
    int? limit,
  }) async {
    await ensureLoaded();
    final repo = await _repo();
    final result = await repo.readAll();

    var entries = result.entries;
    if (category != null) {
      entries = entries.where((e) => e.category == category).toList();
    }
    entries = entries.reversed.toList();
    if (limit != null && entries.length > limit) {
      entries = entries.sublist(0, limit);
    }
    return entries;
  }
}
