enum ButtonRotation { none, deg90, deg180, deg270 }

extension ButtonRotationInfo on ButtonRotation {
  double get turns => switch (this) {
    ButtonRotation.none => 0.0,
    ButtonRotation.deg90 => 0.25,
    ButtonRotation.deg180 => 0.5,
    ButtonRotation.deg270 => 0.75,
  };

  int get quarterTurns => switch (this) {
    ButtonRotation.none => 0,
    ButtonRotation.deg90 => 1,
    ButtonRotation.deg180 => 2,
    ButtonRotation.deg270 => 3,
  };

  int get degrees => switch (this) {
    ButtonRotation.none => 0,
    ButtonRotation.deg90 => 90,
    ButtonRotation.deg180 => 180,
    ButtonRotation.deg270 => 270,
  };

  ButtonRotation get next => switch (this) {
    ButtonRotation.none => ButtonRotation.deg90,
    ButtonRotation.deg90 => ButtonRotation.deg180,
    ButtonRotation.deg180 => ButtonRotation.deg270,
    ButtonRotation.deg270 => ButtonRotation.none,
  };

  String get label => '$degrees°';
}

ButtonRotation buttonRotationFromJson(dynamic value) {
  if (value is num) {
    return switch (value.toInt()) {
      90 => ButtonRotation.deg90,
      180 => ButtonRotation.deg180,
      270 => ButtonRotation.deg270,
      _ => ButtonRotation.none,
    };
  }
  if (value is String) {
    final numeric = int.tryParse(value);
    if (numeric != null) return buttonRotationFromJson(numeric);
    return ButtonRotation.values.firstWhere(
      (rotation) => rotation.name == value,
      orElse: () => ButtonRotation.none,
    );
  }
  return ButtonRotation.none;
}
