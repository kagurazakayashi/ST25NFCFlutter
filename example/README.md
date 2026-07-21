# nfc_ftm_example

Demonstrates how to use the `nfc_ftm` plugin for ST25 NFC tag communication.

## Getting Started

1. Install dependencies:
   ```bash
   cd example && flutter pub get
   ```

2. **Android**: Place `st25sdk-1.10.0.jar` in `android/libs/` before building.

3. **iOS**: Pods are pre-installed. Ensure the NFC capability is enabled in Xcode.

4. Run on a real device (NFC is not available in simulators):
   ```bash
   flutter run
   ```

## Device Testing

### Android

```bash
export JAVA_HOME=/Volumes/d/usr/local/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home
unset ANDROID_USER_HOME
flutter run -d 483fc634
```

### iOS

```bash
flutter run -d 00008030-001650A10281802E
```

## App Usage

1. Tap **Open NFC** to start tag discovery (NDEF mode) — any NFC tag should be detected
2. Tap **Open FTM** to start FTM mode — the app will try to identify an ST25DV tag and initialize FTM
3. Tap **Send FTM DATA** to transmit data to the tag and receive the response
4. Tap **Read NDEF** / **Write NDEF** to test NDEF operations
5. Watch the log area for status messages and progress updates
