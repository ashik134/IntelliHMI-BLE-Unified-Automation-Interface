// ─────────────────────────────────────────────────────────────────────────────
// GridLayoutOption
//
// The set of selectable button-grid shapes for a control screen's page grid
// (see ControlLayoutConfig.gridLayout) — replaces the old fixed 2-column x
// 3-row grid (ButtonConfig.controlGridColumns/controlGridRows) with an
// operator-selectable preset, applied via the Customization Toolbar's Layout
// tool (see GridLayoutToolbar / LayoutEditController.applyGridLayout).
//
// [twoByThree] is the default — it reproduces the pre-existing fixed grid
// exactly, so layouts saved before this field existed keep rendering
// identically (see ControlLayoutConfig.fromJson, which falls back to
// [fallback] when the `gridLayout` key is absent).
//
// Adding a future preset is purely additive: one more enum value here, no
// other file needs to change.
// ─────────────────────────────────────────────────────────────────────────────

enum GridLayoutOption {
  twoByThree(columns: 2, rows: 3),
  twoByTwo(columns: 2, rows: 2),
  threeByTwo(columns: 3, rows: 2),
  threeByThree(columns: 3, rows: 3),
  fourByThree(columns: 4, rows: 3),
  threeByFour(columns: 3, rows: 4),
  fourByFour(columns: 4, rows: 4),
  fourByFive(columns: 4, rows: 5);

  const GridLayoutOption({required this.columns, required this.rows});

  final int columns;
  final int rows;

  int get slotCount => columns * rows;

  String get label => '$columns×$rows';

  bool get isDefault => this == GridLayoutOption.twoByThree;

  static const GridLayoutOption fallback = GridLayoutOption.twoByThree;

  /// Resolves a persisted [ControlLayoutConfig.toJson] `gridLayout` value
  /// back to its enum — an unknown or missing name (older saved JSON, or a
  /// preset removed in a future version) falls back to [fallback] rather
  /// than throwing.
  static GridLayoutOption fromName(String? name) =>
      values.firstWhere((option) => option.name == name, orElse: () => fallback);
}
