# 3DiVi first physical-device milestone

The Face SDK runtime is separately licensed and is not committed to this
repository. Stage it before resolving Flutter dependencies:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  '.\tool\setup_facesdk.ps1' -SdkRoot 'C:\3DiVi\FaceSDK\3_31_0'
flutter pub get
```

The staging script copies only the ARM64 runtime and the resources required for
the first diagnostic milestone:

- Face SDK configuration files
- Face detector `ssyv_light` version 1
- Face fitter `fda` version 1
- Mobile-optimized face-template extractor `100m` version 1
- Face quality resources
- ISO quality-control resources required by the SDK's `core` quality block
- Passive liveness `2d_ensemble_light` version 4
- The separately supplied license

Run a debug build with the diagnostic explicitly enabled:

```powershell
flutter run --dart-define=FACE_SDK_DIAGNOSTICS=true
```

Open **Settings > Developer diagnostics > 3DiVi Face SDK diagnostic**. The
diagnostic does not enroll an operator, create a template, save a photograph, or
grant Control access. It proves service initialization, front-camera geometry,
face detection, quality control, and passive PAD before operator storage is
implemented.
