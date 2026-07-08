# AGENTS.md — nfc_ftm Flutter Plugin

## Project Identity
- **Package**: `nfc_ftm` — Flutter plugin for ST25 NFC tags with FTM (Fast Transfer Mode).
- **Root**: The repo root **is** the plugin package. `example/` is a separate Flutter app.
- **Platforms**: Android (primary, with ST25SDK), iOS (stub, not fully implemented).

## Commands

```bash
# From repo root (plugin):
flutter analyze          # Static analysis
flutter test             # Run plugin unit tests
dart format lib/ test/   # Format code

# From example/ (example app):
cd example
flutter analyze          # Static analysis for example app
flutter test             # Run example unit + integration tests
flutter run              # Run example app on device
```

- No CI/CD workflows exist in this repo.
- There is no `dart run` or `dart compile` entrypoint — this is a library package.

## Architecture

```
lib/
  nfc_ftm.dart                      # Public API class (NfcFtm)
  nfc_ftm_platform_interface.dart   # Abstract platform interface (plugin_platform_interface)
  nfc_ftm_method_channel.dart       # MethodChannel + EventChannel implementation
  nfc_obj.dart                      # Types: NfcTag, NdefTag, NfcState enum, typedefs
android/
  src/main/java/moe/yashi/nfc_ftm/
    NfcFtmPlugin.java               # 819-line native Android plugin (ST25SDK)
    ProgressListener.java           # FTM progress callback interface
ios/
  Classes/                          # iOS stubs (incomplete)
```

## Platform Channel Details (critical)

| Channel | Name | Direction |
|---------|------|-----------|
| MethodChannel | `nfc_ftm_to_native` | Dart → Native |
| EventChannel | `nfc_ftm_to_flutter` | Native → Dart |

**The channel name is NOT the default `package.name/method` pattern.** The test file `test/nfc_ftm_method_channel_test.dart:9` uses the wrong name (`nfc_ftm`), meaning the test is currently broken.

EventChannel message types (key `k`): `onDiscovered`, `toast`, `transmissionProgress`, `receptionProgress`.

## Native Android Dependencies

- Requires `android/libs/st25sdk-1.10.0.jar` (local file, not from Maven).
- Also requires `spongycastle:bcpkix-jdk15on:1.58.0.0` and `commons-lang3:3.5` for ST25SDK.
- `compileSdk = 34`, `minSdk = 21`.

## Test Notes

- `test/nfc_ftm_test.dart` — Verifies default platform instance type. Works standalone.
- `test/nfc_ftm_method_channel_test.dart` — **Broken**: uses wrong channel name `nfc_ftm` (should be `nfc_ftm_to_native`), and test body is effectively empty.
- Example app has `integration_test/plugin_integration_test.dart` (requires device).
- Android native tests use JUnit 4 + Mockito in `android/src/test/`.

## Code Style

- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml` (Flutter's recommended lint set).
- Code comments are in Simplified Chinese.
- `dart format` is the formatter (no custom config).

## Key Gotchas

1. **Channel names are non-standard**: `nfc_ftm_to_native` / `nfc_ftm_to_flutter`. Do not guess the default `package_name/method_name` pattern.
2. **ST25SDK JAR is local**: The build will fail if `android/libs/` is missing the JAR. Do not modify `build.gradle` dependencies without confirming the JAR exists.
3. **The test is broken**: Any agent writing channel tests should use `nfc_ftm_to_native`, not `nfc_ftm`.
4. **iOS is incomplete**: Only Android has real native code. iOS has stub files only.
