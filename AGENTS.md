# AGENTS.md — nfc_ftm Flutter Plugin

## Project Identity
- **Package**: `nfc_ftm` — Flutter plugin for ST25 NFC tags with FTM (Fast Transfer Mode).
- **Root**: The repo root **is** the plugin package. `example/` is a separate Flutter app.
- **Platforms**: Android (ST25SDK JAR v1.10.0), iOS (ST25SDK J2ObjC framework + CoreNFC).

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
  nfc_ftm_platform_interface.dart   # Abstract platform interface
  nfc_ftm_method_channel.dart       # MethodChannel + EventChannel
  nfc_obj.dart                      # Types: NfcTag, NdefTag, NfcState enum
android/
  src/main/java/moe/yashi/nfc_ftm/
    NfcFtmPlugin.java               # Android native plugin (~855 lines)
    ProgressListener.java           # FTM progress callback interface
ios/
  Classes/
    NfcFtmPlugin.swift              # iOS native plugin (~923 lines)
    iOSRFReaderInterface.swift      # CoreNFC → ST25SDK bridge (~180 lines)
    TagError.swift                  # Error enum
    NfcFtmPlugin-Bridging-Header.h  # ObjC bridge for SwiftTryCatch
    SwiftTryCatch.h/.m              # ObjC exception handling for J2ObjC
  Frameworks/
    st25sdkFramework.framework/     # Vendored ST25SDK (J2ObjC binary, ~14 MB)
```

## Platform Channel Details (critical)

| Channel | Name | Direction |
|---------|------|-----------|
| MethodChannel | `nfc_ftm_to_native` | Dart → Native |
| EventChannel | `nfc_ftm_to_flutter` | Native → Dart |

**The channel name is NOT the default `package.name/method` pattern.**

EventChannel message types (key `k`): `onDiscovered`, `toast`, `transmissionProgress`, `receptionProgress`.

## Native Android Dependencies

- Requires `android/libs/st25sdk-1.10.0.jar` (local file, not from Maven).
- Also requires `spongycastle:bcpkix-jdk15on:1.58.0.0` and `commons-lang3:3.5`.
- `compileSdk = 34`, `minSdk = 21`.

## Native iOS Dependencies

- Uses vendored `st25sdkFramework.framework` (J2ObjC-translated ST25SDK, ~14 MB binary).
- Requires `CoreNFC` system framework.
- Minimum deployment target: iOS 14.1.
- FTM and NDEF operations use both ST25SDK and CoreNFC native APIs.

### iOS RFReaderInterface Architecture

The `iOSRFReaderInterface` bridges between the ST25SDK's command format and Apple's CoreNFC API. Key design decisions:

| Command Type | CoreNFC API Used | Notes |
|---|---|---|
| `getSystemInfo` | `NFCISO15693Tag.getSystemInfo()` | Native API, constructs correct ISO15693 response |
| `readSingleBlock` / `readMultipleBlock` | `NFCISO15693Tag.readSingleBlock()` / `readMultipleBlocks()` | CoreNFC handles UID addressing automatically via `isoTag.identifier` |
| Custom ST commands (0xA0-0xDF) | `NFCISO15693Tag.sendRequest()` | Non-addressed mode (flag 0x02), strips SDK's UID from body for config commands, passes mailbox command body as-is |
| `extendedGetSystemInfo` / vicinity | `NFCISO15693Tag.getSystemInfo()` | Falls back to standard system info |

The iOS SDK binary constructs addressed commands with a specific UID byte order that differs from CoreNFC's `isoTag.identifier`. Standard commands work via CoreNFC's native APIs (which use CoreNFC's UID). Custom ST commands must be converted to Android-compatible non-addressed format.

## Test Notes

- `test/nfc_ftm_test.dart` — Verifies default platform instance type. Works standalone.
- `test/nfc_ftm_method_channel_test.dart` — **Broken**: uses wrong channel name `nfc_ftm` (should be `nfc_ftm_to_native`), and test body is effectively empty.
- Example app has `integration_test/plugin_integration_test.dart` (requires device).
- Android native tests use JUnit 4 + Mockito in `android/src/test/`.

## Code Style

- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml`.
- Code comments are in Simplified Chinese.
- `dart format` is the formatter (no custom config).

## Android 端测试方法

Android 测试设备: `483fc634` (PJD110 / OPPO Find X7)

运行命令（从 `example/` 目录）:

```bash
export JAVA_HOME=/Volumes/d/usr/local/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home
unset ANDROID_USER_HOME
flutter run -d 483fc634
```

**注意事项**:
- `ANDROID_USER_HOME` 必须 unset，否则会尝试访问不存在的 `/Volumes/MACAPP/android` 导致 `AccessDeniedException`
- `JAVA_HOME` 必须指向存在的 Java 17 路径
- 如果 NDK 损坏，删除对应目录让 AGP 自动重新下载:
  ```bash
  rm -rf /Volumes/d/sdk/android/ndk/28.2.13676358
  ```
- ANDROID_HOME=`/Volumes/d/sdk/android`，GRADLE_USER_HOME=`/Volumes/d/Users/yashi/gradle`

## iOS 端测试方法

iOS 测试设备: `00008030-001650A10281802E` (e的iPhone)

运行命令（从 `example/` 目录）:

```bash
flutter run -d 00008030-001650A10281802E
```

## Key Gotchas

1. **Channel names are non-standard**: `nfc_ftm_to_native` / `nfc_ftm_to_flutter`. Do not guess the default pattern.
2. **ST25SDK JAR is local**: The build will fail if `android/libs/` is missing the JAR.
3. **The test is broken**: Channel tests should use `nfc_ftm_to_native`, not `nfc_ftm`.
4. **iOS UID byte order**: CoreNFC returns UID in LSB-first order. The SDK constructs commands using CoreNFC's UID via native APIs, so `ST25DVTag` constructor must receive non-reversed UID bytes.
5. **iOS custom commands**: ST proprietary commands (0xA0-0xDF) must be sent in non-addressed mode (flag 0x02) via `sendRequest()`, matching Android's `Iso15693CustomCommand` behavior.
6. **iOS `identifyTypeVProduct`**: The J2ObjC version may not correctly identify ST25DV products. The discovery flow relies on direct `ST25DVTag` construction as a heuristic.
