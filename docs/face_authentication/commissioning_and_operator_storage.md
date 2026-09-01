# Administrator commissioning and operator storage

Administrator authorization, operator face identity, and PLC authentication are
three independent security domains. No credential or key is shared between
them.

## One-time administrator commissioning

There is no default administrator password. Production builds do not expose a
bootstrap form. To commission a new deployment, build or run the application
with the setup surface explicitly enabled:

```powershell
flutter run `
  --dart-define=ADMIN_COMMISSIONING_ENABLED=true `
  --dart-define=FACE_SDK_DIAGNOSTICS=true
```

Open **Settings > Operator Management / Face Registration** and enter the local
PIN or password supplied by the commissioning/deployment process. Do not put the
credential itself in a Dart define, source file, command line, PLC configuration,
or deployment log.

The application stores only a random 32-byte salt and a 32-byte
PBKDF2-HMAC-SHA256 verifier (210,000 iterations). Android performs derivation on
a dedicated background executor. The verifier is protected by
`flutter_secure_storage` in the isolated `intellihmi_admin_auth_v1` Android
Keystore namespace.

After successful commissioning, deploy the normal build without
`ADMIN_COMMISSIONING_ENABLED`. Existing authorization remains available, but an
uncommissioned production build remains locked. Administrator authorization
expires after five minutes and immediately when the app backgrounds.

## Offline operator persistence

Operator data is stored in `intellihmi_operator_auth_v1.db` using SQLite with
foreign keys and secure deletion enabled. The schema enforces:

- a unique normalized Employee ID, including against deleted tombstones;
- exactly one face-template row per operator;
- transactional operator plus mandatory-template creation;
- transactional face replacement so the old enrollment survives a failed
  re-enrollment;
- audit snapshots that remain meaningful after operator deletion.

Each biometric template is encrypted with AES-256-GCM and authenticated metadata.
Every enrollment receives a new random data key. Those keys live only in the
separate `intellihmi_face_template_keys_v1` Keystore namespace. Deleting or
re-enrolling removes the old data key, making residual ciphertext unusable.
Android application backup is disabled.

No camera frame or enrollment photograph is persisted. Audit records never
contain templates, embeddings, SDK buffers, or raw images.

## 3DiVi recognition configuration

The enrollment pipeline uses the official SDK blocks:

1. `FACE_DETECTOR` / `ssyv_light` version 1
2. `FACE_FITTER` / `fda` version 1
3. `QUALITY_CONTROL` / `core`
4. `LIVENESS_ESTIMATOR` / `2d_ensemble_light` version 4
5. `FACE_TEMPLATE_EXTRACTOR` / `100m` version 1
6. `VERIFICATION_MODULE` / `100m` version 1 for duplicate-face prevention

The official SDK documentation identifies `100m` as a speed-optimized mobile
choice. Matching extractor and verifier modifications is mandatory. The current
duplicate-face score threshold is 0.90 and requires population/device validation
before production sign-off.
