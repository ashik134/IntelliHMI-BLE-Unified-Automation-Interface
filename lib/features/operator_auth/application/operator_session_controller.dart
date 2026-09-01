import 'package:flutter/widgets.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';

/// In-memory, foreground-only human identity for the current PLC connection.
/// Nothing here authenticates the PLC and nothing is persisted across app
/// restarts. PLC credentials remain owned by the existing CraneController.
class OperatorSessionController extends ChangeNotifier
    with WidgetsBindingObserver {
  OperatorSessionController() {
    WidgetsBinding.instance.addObserver(this);
  }

  OperatorRecord? _operator;
  String? _plcConnectionId;
  DateTime? _authenticatedAt;

  OperatorRecord? get operator => _operator;
  DateTime? get authenticatedAt => _authenticatedAt;
  bool get hasFaceIdentity => _operator != null;

  bool isAuthorizedFor(String? plcConnectionId) =>
      plcConnectionId != null &&
      _operator != null &&
      _operator!.enabled &&
      !_operator!.isDeleted &&
      _plcConnectionId == plcConnectionId;

  void establish({
    required OperatorRecord operator,
    required String plcConnectionId,
  }) {
    if (!operator.enabled || operator.isDeleted) {
      throw ArgumentError(
        'A disabled or deleted operator cannot own a session.',
      );
    }
    _operator = operator;
    _plcConnectionId = plcConnectionId;
    _authenticatedAt = DateTime.now().toUtc();
    notifyListeners();
  }

  void clear() {
    if (_operator == null && _plcConnectionId == null) return;
    _operator = null;
    _plcConnectionId = null;
    _authenticatedAt = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _operator = null;
    _plcConnectionId = null;
    _authenticatedAt = null;
    super.dispose();
  }
}
