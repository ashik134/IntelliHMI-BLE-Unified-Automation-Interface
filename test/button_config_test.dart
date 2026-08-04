// Regression guard for the fix-#1/fix-#2 additions to ButtonConfig:
//   - iconKey -> icon resolution via the curated button_icon_registry, which
//     is what makes an icon picked from the customization sheet actually
//     survive a save/reload (a bare codePoint alone never did — see
//     ButtonConfig.iconKey's doc comment).
//   - legacy JSON with no iconKey at all keeps the pre-existing exact
//     behavior: icon always restores to null.
//   - catalogEntryId round-trips, which is what lets "Reset to default"
//     know which exact catalogue variant a placed widget came from.

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_icon_registry.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

ButtonConfig _button({String? iconKey, String? catalogEntryId}) => ButtonConfig(
  id: 'placed_1',
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  label: 'Test',
  iconKey: iconKey,
  icon: iconForKey(iconKey),
  catalogEntryId: catalogEntryId,
);

void main() {
  test('a curated icon key resolves to a real IconData through toJson/fromJson', () {
    final original = _button(iconKey: 'bolt');
    expect(original.icon, isNotNull);

    final restored = ButtonConfig.fromJson(original.toJson());
    expect(restored.iconKey, 'bolt');
    expect(restored.icon, isNotNull);
    expect(restored.icon!.codePoint, Icons.bolt_rounded.codePoint);
    expect(restored.icon!.fontFamily, Icons.bolt_rounded.fontFamily);
  });

  test('no iconKey (fresh button, never touched the icon picker) round-trips '
      'icon as null', () {
    final original = _button();
    final restored = ButtonConfig.fromJson(original.toJson());
    expect(restored.iconKey, isNull);
    expect(restored.icon, isNull);
  });

  test('legacy JSON with a bare codePoint but no iconKey still restores '
      'icon to null — unchanged pre-existing behavior', () {
    final json = _button().toJson();
    json.remove('iconKey');
    json['icon'] = Icons.bolt_rounded.codePoint;

    final restored = ButtonConfig.fromJson(json);
    expect(restored.icon, isNull);
  });

  test('an unknown/stale iconKey resolves to null, matching "no icon" '
      'rather than throwing', () {
    final json = _button().toJson();
    json['iconKey'] = 'not_a_real_key';

    final restored = ButtonConfig.fromJson(json);
    expect(restored.icon, isNull);
    expect(restored.iconKey, 'not_a_real_key');
  });

  test('clearIcon/clearIconKey copyWith clears both fields together', () {
    final withIcon = _button(iconKey: 'warning');
    final cleared = withIcon.copyWith(clearIcon: true, clearIconKey: true);
    expect(cleared.icon, isNull);
    expect(cleared.iconKey, isNull);
  });

  test('catalogEntryId round-trips through toJson/fromJson', () {
    final original = _button(catalogEntryId: 'digitalControls.Push Buttons.Latching Push Button');
    final restored = ButtonConfig.fromJson(original.toJson());
    expect(restored.catalogEntryId, original.catalogEntryId);
  });

  test('no catalogEntryId (pre-existing/non-catalogue button) round-trips as null', () {
    final restored = ButtonConfig.fromJson(_button().toJson());
    expect(restored.catalogEntryId, isNull);
  });

  test('clearCatalogEntryId copyWith clears the field', () {
    final withEntry = _button(catalogEntryId: 'some.entry.id');
    final cleared = withEntry.copyWith(clearCatalogEntryId: true);
    expect(cleared.catalogEntryId, isNull);
  });
}
