import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SavedTemplate
//
// A user-created "Save as Template" snapshot — a named copy of a
// ControlLayoutConfig, scoped to the LayoutBucket it was captured from since
// PLC mappings and axis composition differ per PLC type. ControlLayoutConfig
// only ever holds static configuration (widgets, positions, sizes, pages,
// labels, styles, PLC mappings) — never runtime/live state (button/joystick
// live values, PLC outputs, BLE connection, E-Stop latch), which lives
// entirely on CraneController — so a saved template can never capture it.
// ─────────────────────────────────────────────────────────────────────────────

class SavedTemplate {
  const SavedTemplate({
    required this.id,
    required this.name,
    required this.bucket,
    required this.config,
    required this.createdAt,
  });

  final String id;
  final String name;
  final LayoutBucket bucket;
  final ControlLayoutConfig config;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bucket': bucket.name,
    'config': config.toJson(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedTemplate.fromJson(Map<String, dynamic> json) {
    return SavedTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      bucket: LayoutBucket.values.firstWhere(
        (b) => b.name == json['bucket'],
        orElse: () => LayoutBucket.plc14,
      ),
      config: ControlLayoutConfig.fromJson(
        json['config'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
