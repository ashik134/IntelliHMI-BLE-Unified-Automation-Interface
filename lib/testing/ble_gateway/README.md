# BLE Gateway Test Harness

Temporary local-network BLE gateway for testing the HMI on a tablet whose BLE is
not reliable.

## Run Target

Run the isolated test launcher on both Android devices:

```powershell
flutter run -t lib/testing/ble_gateway/main_ble_gateway_test.dart
```

Use **Phone Gateway Mode** on the Android phone. Start the WebSocket server and
note the displayed IP address and port.

Use **Tablet Remote BLE Mode** on the Samsung tablet. Enter the phone endpoint,
connect, then use the existing HMI scan/login/control flow.

## Boundaries

- The phone is the only device that scans and talks to BLE.
- The tablet talks to the phone over WebSocket JSON.
- No tablet-to-phone heartbeat/watchdog is implemented in this harness.
- Production `lib/main.dart` does not launch this code.
- Remove this folder and the `BleTransport` test hook when this harness is no
  longer needed.

## Wire Messages

Tablet to phone:

- `scan`
- `stopScan`
- `connect`
- `disconnect`
- `digitalWrite`
- `write`
- `read`

Phone to tablet:

- `scanResult`
- `bleStatus`
- `notification`
- `readResult`
- `error`
- `log`
