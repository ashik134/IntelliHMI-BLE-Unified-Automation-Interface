import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';

void main() {
  test('normal mode reserves only the accent-line height', () {
    const footer = ControlModeAppBarFooter(isEditing: false);

    expect(footer.preferredSize.height, ControlModeAppBarFooter.normalHeight);
    expect(footer.preferredSize.height, 3);
  });

  test('edit mode reserves the full outputs-blocked banner height', () {
    const footer = ControlModeAppBarFooter(isEditing: true);

    expect(footer.preferredSize.height, ControlModeAppBarFooter.editingHeight);
    expect(footer.preferredSize.height, 28);
  });
}
