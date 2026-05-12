import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/models/hmi_layout_models.dart';
import 'package:rev6_crane_control_ops/services/hmi_profile_repository.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

class HmiLayoutController extends ChangeNotifier {
  HmiLayoutController({
    required CraneController craneController,
    HmiProfileRepository? repository,
  }) : _craneController = craneController,
       _repository = repository ?? HmiProfileRepository() {
    _craneController.addListener(_onCraneChanged);
    initialize();
  }

  final CraneController _craneController;
  final HmiProfileRepository _repository;

  bool _loading = true;
  bool _initialized = false;
  bool _editMode = false;
  bool _saving = false;

  String? _activeProfileId;
  String? _selectedWidgetId;

  final List<HmiLayoutProfile> _profiles = [];
  final Map<String, double> _analogOutputs = <String, double>{};
  final Map<String, bool> _digitalOverrides = <String, bool>{};
  final Map<String, List<double>> _analogTrend = <String, List<double>>{};
  final List<LayoutIssue> _layoutIssues = [];
  Map<String, int> _lastAnalogSnapshot = const <String, int>{};
  int _idCounter = 0;

  bool get loading => _loading;
  bool get saving => _saving;
  bool get editMode => _editMode;
  List<HmiLayoutProfile> get profiles => List.unmodifiable(_profiles);
  List<LayoutIssue> get layoutIssues => List.unmodifiable(_layoutIssues);
  String? get selectedWidgetId => _selectedWidgetId;

  String get activeProfileId {
    final fallback = _profiles.isNotEmpty ? _profiles.first.id : null;
    return _activeProfileId ?? fallback ?? '';
  }

  HmiLayoutProfile? get activeProfile {
    if (_profiles.isEmpty) {
      return null;
    }
    final id = activeProfileId;
    for (final profile in _profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return _profiles.first;
  }

  HmiWidgetConfig? get selectedWidget {
    final profile = activeProfile;
    final selectedId = _selectedWidgetId;
    if (profile == null || selectedId == null) {
      return null;
    }
    return profile.widgetById(selectedId);
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    _loading = true;
    notifyListeners();
    final loaded = await _repository.loadProfiles();
    _profiles
      ..clear()
      ..addAll(loaded);

    if (_profiles.isEmpty) {
      _profiles.add(
        _repository.buildDefaultProfile(
          deviceType: _normalizedDeviceType,
          analogInputCount: _deriveAnalogInputCount(),
        ),
      );
      await _repository.saveProfiles(_profiles);
    }

    final storedActiveId = await _repository.loadActiveProfileId();
    _activeProfileId = _profiles.any((profile) => profile.id == storedActiveId)
        ? storedActiveId
        : _profiles.first.id;

    _rebuildValidationIssues();
    _loading = false;
    notifyListeners();
  }

  Future<void> setActiveProfile(String profileId) async {
    if (!_profiles.any((profile) => profile.id == profileId)) {
      return;
    }
    _activeProfileId = profileId;
    _selectedWidgetId = null;
    _rebuildValidationIssues();
    notifyListeners();
    await _repository.saveActiveProfileId(profileId);
  }

  Future<void> createProfileFromActive({String? name}) async {
    final source = activeProfile;
    if (source == null) {
      return;
    }
    final profile = source.copyWith(
      id: _newProfileId(),
      name: (name == null || name.trim().isEmpty)
          ? '${source.name} Copy'
          : name.trim(),
      updatedAt: DateTime.now(),
      widgets: source.widgets
          .map(
            (widget) => widget.copyWith(
              id: _newWidgetId(),
              layout: widget.layout.moveBy(0.015, 0.015),
            ),
          )
          .toList(),
    );
    _profiles.insert(0, profile);
    _activeProfileId = profile.id;
    _selectedWidgetId = null;
    _rebuildValidationIssues();
    notifyListeners();
    await _persist();
  }

  Future<void> renameActiveProfile(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _mutateActiveProfile((profile) {
      return profile.copyWith(name: trimmed, updatedAt: DateTime.now());
    });
    await _persist();
  }

  Future<void> deleteProfile(String profileId) async {
    if (_profiles.length <= 1) {
      return;
    }
    _profiles.removeWhere((profile) => profile.id == profileId);
    if (!_profiles.any((profile) => profile.id == _activeProfileId)) {
      _activeProfileId = _profiles.first.id;
    }
    _selectedWidgetId = null;
    _rebuildValidationIssues();
    notifyListeners();
    await _persist();
  }

  Future<void> setTemplate(String template) async {
    _mutateActiveProfile(
      (profile) =>
          profile.copyWith(template: template, updatedAt: DateTime.now()),
    );
    await _persist();
  }

  void setEditMode(bool enabled) {
    if (_editMode == enabled) {
      return;
    }
    _editMode = enabled;
    if (!enabled) {
      _selectedWidgetId = null;
    }
    notifyListeners();
  }

  Future<void> addWidget(HmiWidgetType type) async {
    final widget = _repository.buildWidgetTemplate(type);
    _mutateActiveProfile((profile) {
      final shifted = _findNonOverlappingLayout(profile.widgets, widget.layout);
      final updatedWidgets = [
        ...profile.widgets,
        widget.copyWith(layout: shifted),
      ];
      return profile.copyWith(
        widgets: updatedWidgets,
        updatedAt: DateTime.now(),
      );
    });
    _selectedWidgetId = widget.id;
    await _persist();
  }

  Future<void> removeSelectedWidget() async {
    final widgetId = _selectedWidgetId;
    if (widgetId == null) {
      return;
    }
    await removeWidget(widgetId);
  }

  Future<void> removeWidget(String widgetId) async {
    _mutateActiveProfile((profile) {
      final updatedWidgets = profile.widgets
          .where((widget) => widget.id != widgetId)
          .toList();
      return profile.copyWith(
        widgets: updatedWidgets,
        updatedAt: DateTime.now(),
      );
    });
    if (_selectedWidgetId == widgetId) {
      _selectedWidgetId = null;
    }
    await _persist();
  }

  Future<void> selectWidget(String? widgetId) async {
    _selectedWidgetId = widgetId;
    notifyListeners();
  }

  Future<void> moveWidgetByPixels({
    required String widgetId,
    required Offset deltaPixels,
    required Size canvasSize,
  }) async {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }
    final deltaX = deltaPixels.dx / canvasSize.width;
    final deltaY = deltaPixels.dy / canvasSize.height;
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(layout: widget.layout.moveBy(deltaX, deltaY));
    }, persist: false);
  }

  Future<void> resizeWidgetByPixels({
    required String widgetId,
    required Offset deltaPixels,
    required Size canvasSize,
  }) async {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) {
      return;
    }
    final deltaW = deltaPixels.dx / canvasSize.width;
    final deltaH = deltaPixels.dy / canvasSize.height;
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(layout: widget.layout.resizeBy(deltaW, deltaH));
    }, persist: false);
  }

  Future<void> finalizeLayoutGesture() async {
    await _persist();
  }

  Future<void> updateWidgetLabel(String widgetId, String label) async {
    _mutateWidget(
      widgetId,
      (widget) => widget.copyWith(
        label: label.trim().isEmpty ? widget.label : label.trim(),
      ),
    );
    await _persist();
  }

  Future<void> updateWidgetType(String widgetId, HmiWidgetType type) async {
    _mutateWidget(widgetId, (widget) {
      final template = _repository.buildWidgetTemplate(type);
      return widget.copyWith(
        type: type,
        behavior: template.behavior,
        binding: template.binding,
        color: template.color,
      );
    });
    await _persist();
  }

  Future<void> updateWidgetBinding(
    String widgetId, {
    String? primaryTag,
    String? secondaryTag,
    String? tertiaryTag,
    String? quaternaryTag,
    bool? invert,
  }) async {
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(
        binding: widget.binding.copyWith(
          primaryTag: primaryTag,
          secondaryTag: secondaryTag,
          tertiaryTag: tertiaryTag,
          quaternaryTag: quaternaryTag,
          invert: invert,
        ),
      );
    });
    await _persist();
  }

  Future<void> updateWidgetHoldMode(
    String widgetId,
    ControlHoldMode holdMode,
  ) async {
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(
        behavior: widget.behavior.copyWith(holdMode: holdMode),
      );
    });
    await _persist();
  }

  Future<void> updateWidgetTogglePattern(
    String widgetId,
    TogglePattern togglePattern,
  ) async {
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(
        behavior: widget.behavior.copyWith(togglePattern: togglePattern),
      );
    });
    await _persist();
  }

  Future<void> updateWidgetBehavior(
    String widgetId,
    HmiBehaviorConfig behavior,
  ) async {
    _mutateWidget(widgetId, (widget) {
      return widget.copyWith(behavior: behavior);
    });
    await _persist();
  }

  Future<void> updateWidgetVisibility(String widgetId, bool visible) async {
    _mutateWidget(widgetId, (widget) => widget.copyWith(visible: visible));
    await _persist();
  }

  Future<void> updateWidgetEnabled(String widgetId, bool enabled) async {
    _mutateWidget(widgetId, (widget) => widget.copyWith(enabled: enabled));
    await _persist();
  }

  Future<void> updateWidgetColor(String widgetId, Color color) async {
    _mutateWidget(widgetId, (widget) => widget.copyWith(color: color));
    await _persist();
  }

  Future<void> setAnalogOutputValue(String tag, double value) async {
    _analogOutputs[tag] = value;
    notifyListeners();
  }

  double getAnalogValue(String tag) {
    final fromPlc = _craneController.analogValues[tag];
    if (fromPlc != null) {
      return fromPlc.toDouble();
    }
    return _analogOutputs[tag] ?? 0;
  }

  List<double> analogTrend(String tag) {
    return List.unmodifiable(_analogTrend[tag] ?? const <double>[]);
  }

  bool getDigitalOverride(String tag) {
    return _digitalOverrides[tag] ?? false;
  }

  Future<void> setDigitalOverride(String tag, bool value) async {
    _digitalOverrides[tag] = value;
    notifyListeners();
    await _applyTagCommand(tag, value: value);
  }

  Future<void> setHoistControl(String tag, ControlState state) async {
    final normalizedTag = tag.trim().toUpperCase();
    if (normalizedTag.contains('DOWN')) {
      await _craneController.setHoistCommand(isUp: false, state: state);
      return;
    }
    await _craneController.setHoistCommand(isUp: true, state: state);
  }

  Future<void> triggerEmergencyStop() async {
    await _craneController.triggerEStop();
  }

  Future<void> resetEmergencyStop() async {
    await _craneController.resetEStop();
  }

  Future<void> _applyTagCommand(String tag, {required bool value}) async {
    final normalized = tag.trim().toUpperCase();
    if (normalized.contains('ESTOP')) {
      if (value) {
        await _craneController.triggerEStop();
      } else {
        await _craneController.resetEStop();
      }
      return;
    }

    if (normalized.contains('HOIST_UP')) {
      await _craneController.setHoistCommand(
        isUp: true,
        state: value ? ControlState.slow : ControlState.idle,
      );
      return;
    }

    if (normalized.contains('HOIST_DOWN')) {
      await _craneController.setHoistCommand(
        isUp: false,
        state: value ? ControlState.slow : ControlState.idle,
      );
      return;
    }

    if (normalized.contains('HOIST_FAST')) {
      final hoistState = _craneController.hoistState;
      if (hoistState == HoistState.idle) {
        return;
      }
      if (value) {
        if (hoistState == HoistState.upSlow) {
          await _craneController.setHoistCommand(
            isUp: true,
            state: ControlState.fast,
          );
          return;
        }
        if (hoistState == HoistState.downSlow) {
          await _craneController.setHoistCommand(
            isUp: false,
            state: ControlState.fast,
          );
          return;
        }
      } else {
        if (hoistState == HoistState.upFast) {
          await _craneController.setHoistCommand(
            isUp: true,
            state: ControlState.slow,
          );
          return;
        }
        if (hoistState == HoistState.downFast) {
          await _craneController.setHoistCommand(
            isUp: false,
            state: ControlState.slow,
          );
          return;
        }
      }
    }
  }

  HmiWidgetLayout _findNonOverlappingLayout(
    List<HmiWidgetConfig> existingWidgets,
    HmiWidgetLayout base,
  ) {
    var candidate = base.normalized();
    var tries = 0;
    while (tries < 20) {
      final overlapping = existingWidgets.any(
        (widget) => widget.visible && widget.layout.overlaps(candidate),
      );
      if (!overlapping) {
        return candidate;
      }
      candidate = candidate.moveBy(0.03, 0.03);
      tries++;
    }
    return candidate;
  }

  void _onCraneChanged() {
    final analogValues = _craneController.analogValues;
    if (_mapEquals(analogValues, _lastAnalogSnapshot)) {
      return;
    }
    _lastAnalogSnapshot = Map<String, int>.from(analogValues);
    for (final entry in analogValues.entries) {
      final key = entry.key;
      final value = entry.value.toDouble();
      final history = _analogTrend.putIfAbsent(key, () => <double>[]);
      history.add(value);
      if (history.length > 40) {
        history.removeRange(0, history.length - 40);
      }
    }
    notifyListeners();
  }

  bool _mapEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  int _deriveAnalogInputCount() {
    final fromDevice = _craneController.analogValues.keys
        .where((key) => key.toUpperCase().startsWith('A'))
        .length;
    return max(2, fromDevice);
  }

  String get _normalizedDeviceType {
    final name =
        _craneController.connectedDeviceName ?? BLEConstants.deviceName;
    return name.replaceAll(' ', '_').toLowerCase();
  }

  void _mutateWidget(
    String widgetId,
    HmiWidgetConfig Function(HmiWidgetConfig widget) mutate, {
    bool persist = false,
  }) {
    _mutateActiveProfile((profile) {
      final updatedWidgets = profile.widgets.map((widget) {
        if (widget.id != widgetId) {
          return widget;
        }
        return mutate(widget);
      }).toList();
      return profile.copyWith(
        widgets: updatedWidgets,
        updatedAt: DateTime.now(),
      );
    });
    if (persist) {
      _persist();
    }
  }

  void _mutateActiveProfile(
    HmiLayoutProfile Function(HmiLayoutProfile profile) mutate,
  ) {
    final profile = activeProfile;
    if (profile == null) {
      return;
    }
    final index = _profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      return;
    }
    _profiles[index] = mutate(profile);
    _rebuildValidationIssues();
    notifyListeners();
  }

  void _rebuildValidationIssues() {
    _layoutIssues
      ..clear()
      ..addAll(_validateActiveProfile());
  }

  List<LayoutIssue> _validateActiveProfile() {
    final profile = activeProfile;
    if (profile == null) {
      return const <LayoutIssue>[];
    }

    final issues = <LayoutIssue>[];
    final visibleWidgets = profile.widgets
        .where((widget) => widget.visible)
        .toList();

    for (final widget in visibleWidgets) {
      final layout = widget.layout;
      if (layout.x < 0 ||
          layout.y < 0 ||
          layout.x + layout.width > 1 ||
          layout.y + layout.height > 1) {
        issues.add(
          LayoutIssue(
            type: LayoutIssueType.outOfBounds,
            widgetId: widget.id,
            message: '${widget.label} is outside layout boundaries.',
          ),
        );
      }

      final requiresBinding =
          widget.type != HmiWidgetType.valueIndicator &&
          widget.type != HmiWidgetType.analogMeter;
      if (requiresBinding && widget.binding.primaryTag.trim().isEmpty) {
        issues.add(
          LayoutIssue(
            type: LayoutIssueType.missingBinding,
            widgetId: widget.id,
            message: '${widget.label} is missing a primary PLC tag.',
          ),
        );
      }
    }

    for (var i = 0; i < visibleWidgets.length; i++) {
      for (var j = i + 1; j < visibleWidgets.length; j++) {
        final left = visibleWidgets[i];
        final right = visibleWidgets[j];
        if (left.layout.overlaps(right.layout)) {
          issues.add(
            LayoutIssue(
              type: LayoutIssueType.overlap,
              widgetId: left.id,
              message: '${left.label} overlaps with ${right.label}.',
            ),
          );
        }
      }
    }
    return issues;
  }

  Future<void> _persist() async {
    if (_saving) {
      return;
    }
    _saving = true;
    notifyListeners();
    try {
      await _repository.saveProfiles(_profiles);
      if (_activeProfileId != null) {
        await _repository.saveActiveProfileId(_activeProfileId!);
      }
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  String _newProfileId() {
    _idCounter++;
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'profile_${now}_${_profiles.length}_$_idCounter';
  }

  String _newWidgetId() {
    _idCounter++;
    final now = DateTime.now().microsecondsSinceEpoch;
    return 'widget_${now}_$_idCounter';
  }

  @override
  void dispose() {
    _craneController.removeListener(_onCraneChanged);
    super.dispose();
  }
}
