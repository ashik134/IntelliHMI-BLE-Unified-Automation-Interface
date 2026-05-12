import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev6_crane_control_ops/models/hmi_layout_models.dart';

class HmiProfileRepository {
  static const String _profilesKey = 'hmi_layout_profiles_v1';
  static const String _activeProfileIdKey = 'hmi_active_profile_id_v1';
  int _idCounter = 0;

  Future<List<HmiLayoutProfile>> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => HmiLayoutProfile.fromJson(item.cast<String, dynamic>()),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfiles(List<HmiLayoutProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      profiles.map((profile) => profile.toJson()).toList(),
    );
    await prefs.setString(_profilesKey, payload);
  }

  Future<String?> loadActiveProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProfileIdKey);
  }

  Future<void> saveActiveProfileId(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileIdKey, profileId);
  }

  HmiLayoutProfile buildDefaultProfile({
    required String deviceType,
    int analogInputCount = 2,
  }) {
    final widgets = <HmiWidgetConfig>[
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.estop,
        label: 'Swipe To Emergency Stop',
        layout: const HmiWidgetLayout(
          x: 0.02,
          y: 0.02,
          width: 0.96,
          height: 0.13,
        ),
        binding: const PlcBindingConfig(primaryTag: 'ESTOP'),
        color: const Color(0xFFDA3633),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.hoistSlider,
        label: 'Hoist Up',
        layout: const HmiWidgetLayout(
          x: 0.02,
          y: 0.19,
          width: 0.30,
          height: 0.42,
        ),
        binding: const PlcBindingConfig(primaryTag: 'HOIST_UP'),
        color: const Color(0xFF238636),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.hoistSlider,
        label: 'Hoist Down',
        layout: const HmiWidgetLayout(
          x: 0.34,
          y: 0.19,
          width: 0.30,
          height: 0.42,
        ),
        binding: const PlcBindingConfig(primaryTag: 'HOIST_DOWN'),
        color: const Color(0xFF1F6FEB),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.toggleSwitch,
        label: 'Fast Mode',
        layout: const HmiWidgetLayout(
          x: 0.66,
          y: 0.19,
          width: 0.32,
          height: 0.17,
        ),
        binding: const PlcBindingConfig(primaryTag: 'HOIST_FAST'),
        behavior: const HmiBehaviorConfig(
          holdMode: ControlHoldMode.latching,
          togglePattern: TogglePattern.zeroLatched,
        ),
        color: const Color(0xFFD29922),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.digitalJoystick,
        label: 'Digital Joystick',
        layout: const HmiWidgetLayout(
          x: 0.66,
          y: 0.38,
          width: 0.32,
          height: 0.24,
        ),
        binding: const PlcBindingConfig(
          primaryTag: 'HOIST_UP',
          secondaryTag: 'HOIST_DOWN',
          tertiaryTag: 'HOIST_FAST',
        ),
        behavior: const HmiBehaviorConfig(
          enableXAxis: false,
          enableYAxis: true,
          stepCountY: 2,
          twoStepMode: true,
        ),
        color: const Color(0xFF4BB7F3),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.potentiometer,
        label: 'Potentiometer',
        layout: const HmiWidgetLayout(
          x: 0.02,
          y: 0.63,
          width: 0.30,
          height: 0.22,
        ),
        binding: const PlcBindingConfig(primaryTag: 'ANALOG_OUT_1'),
        behavior: const HmiBehaviorConfig(
          holdMode: ControlHoldMode.springReturn,
          minValue: -100,
          maxValue: 100,
          unit: '%',
        ),
        color: const Color(0xFF58A6FF),
      ),
      _defaultWidget(
        id: _newWidgetId(),
        type: HmiWidgetType.analogJoystick,
        label: 'Analog Joystick',
        layout: const HmiWidgetLayout(
          x: 0.34,
          y: 0.63,
          width: 0.30,
          height: 0.22,
        ),
        binding: const PlcBindingConfig(
          primaryTag: 'ANALOG_X',
          secondaryTag: 'ANALOG_Y',
        ),
        behavior: const HmiBehaviorConfig(
          twoAxis: true,
          enableXAxis: true,
          enableYAxis: true,
          deadZonePercent: 10,
          minValue: -100,
          maxValue: 100,
          unit: '%',
        ),
        color: const Color(0xFF3FB950),
      ),
    ];

    for (var index = 0; index < analogInputCount; index++) {
      widgets.add(
        _defaultWidget(
          id: _newWidgetId(),
          type: HmiWidgetType.analogMeter,
          label: 'Analog A${index + 1}',
          layout: HmiWidgetLayout(
            x: 0.66,
            y: 0.64 + (index * 0.11),
            width: 0.32,
            height: 0.10,
          ),
          binding: PlcBindingConfig(primaryTag: 'A${index + 1}'),
          behavior: const HmiBehaviorConfig(
            minValue: 0,
            maxValue: 1023,
            unit: 'raw',
            warningThreshold: 780,
            alarmThreshold: 920,
          ),
          color: const Color(0xFFD29922),
        ),
      );
    }

    return HmiLayoutProfile(
      id: _newProfileId(),
      name: 'Default $deviceType',
      deviceType: deviceType,
      updatedAt: DateTime.now(),
      widgets: widgets,
      version: 1,
      template: 'free',
    );
  }

  HmiWidgetConfig buildWidgetTemplate(HmiWidgetType type) {
    final id = _newWidgetId();
    return switch (type) {
      HmiWidgetType.estop => _defaultWidget(
        id: id,
        type: type,
        label: 'Emergency Stop',
        layout: const HmiWidgetLayout(
          x: 0.05,
          y: 0.05,
          width: 0.55,
          height: 0.14,
        ),
        binding: const PlcBindingConfig(primaryTag: 'ESTOP'),
        color: const Color(0xFFDA3633),
      ),
      HmiWidgetType.hoistSlider => _defaultWidget(
        id: id,
        type: type,
        label: 'Hoist Slider',
        layout: const HmiWidgetLayout(
          x: 0.05,
          y: 0.22,
          width: 0.28,
          height: 0.36,
        ),
        binding: const PlcBindingConfig(primaryTag: 'HOIST_UP'),
        behavior: const HmiBehaviorConfig(
          holdMode: ControlHoldMode.springReturn,
        ),
        color: const Color(0xFF238636),
      ),
      HmiWidgetType.potentiometer => _defaultWidget(
        id: id,
        type: type,
        label: 'Potentiometer',
        layout: const HmiWidgetLayout(
          x: 0.35,
          y: 0.22,
          width: 0.28,
          height: 0.22,
        ),
        binding: const PlcBindingConfig(primaryTag: 'ANALOG_OUT_1'),
        behavior: const HmiBehaviorConfig(
          minValue: -100,
          maxValue: 100,
          unit: '%',
        ),
        color: const Color(0xFF58A6FF),
      ),
      HmiWidgetType.analogJoystick => _defaultWidget(
        id: id,
        type: type,
        label: 'Analog Joystick',
        layout: const HmiWidgetLayout(
          x: 0.35,
          y: 0.46,
          width: 0.30,
          height: 0.30,
        ),
        binding: const PlcBindingConfig(
          primaryTag: 'ANALOG_X',
          secondaryTag: 'ANALOG_Y',
        ),
        behavior: const HmiBehaviorConfig(twoAxis: true, enableYAxis: true),
        color: const Color(0xFF3FB950),
      ),
      HmiWidgetType.digitalJoystick => _defaultWidget(
        id: id,
        type: type,
        label: 'Digital Joystick',
        layout: const HmiWidgetLayout(
          x: 0.66,
          y: 0.22,
          width: 0.30,
          height: 0.30,
        ),
        binding: const PlcBindingConfig(
          primaryTag: 'HOIST_UP',
          secondaryTag: 'HOIST_DOWN',
        ),
        behavior: const HmiBehaviorConfig(enableYAxis: true, stepCountY: 2),
        color: const Color(0xFF4BB7F3),
      ),
      HmiWidgetType.toggleSwitch => _defaultWidget(
        id: id,
        type: type,
        label: 'Toggle',
        layout: const HmiWidgetLayout(
          x: 0.66,
          y: 0.54,
          width: 0.30,
          height: 0.15,
        ),
        binding: const PlcBindingConfig(primaryTag: 'Q0.1'),
        behavior: const HmiBehaviorConfig(
          holdMode: ControlHoldMode.latching,
          togglePattern: TogglePattern.zeroLatched,
        ),
        color: const Color(0xFFD29922),
      ),
      HmiWidgetType.analogMeter => _defaultWidget(
        id: id,
        type: type,
        label: 'Analog Meter',
        layout: const HmiWidgetLayout(
          x: 0.66,
          y: 0.71,
          width: 0.30,
          height: 0.13,
        ),
        binding: const PlcBindingConfig(primaryTag: 'A1'),
        behavior: const HmiBehaviorConfig(
          minValue: 0,
          maxValue: 1023,
          unit: 'raw',
        ),
        color: const Color(0xFFD29922),
      ),
      HmiWidgetType.valueIndicator => _defaultWidget(
        id: id,
        type: type,
        label: 'Value',
        layout: const HmiWidgetLayout(
          x: 0.05,
          y: 0.78,
          width: 0.25,
          height: 0.12,
        ),
        binding: const PlcBindingConfig(primaryTag: 'A1'),
        color: const Color(0xFF8B949E),
      ),
    };
  }

  HmiWidgetConfig _defaultWidget({
    required String id,
    required HmiWidgetType type,
    required String label,
    required HmiWidgetLayout layout,
    required PlcBindingConfig binding,
    HmiBehaviorConfig behavior = const HmiBehaviorConfig(),
    Color color = const Color(0xFF4BB7F3),
  }) {
    return HmiWidgetConfig(
      id: id,
      type: type,
      label: label,
      layout: layout.normalized(),
      binding: binding,
      behavior: behavior,
      color: color,
    );
  }

  String _newProfileId() {
    _idCounter++;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'profile_${micros}_$_idCounter';
  }

  String _newWidgetId() {
    _idCounter++;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'widget_${micros}_$_idCounter';
  }
}
