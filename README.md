# nfc_ftm

Flutter plugin for ST25 NFC tags with FTM (Fast Transfer Mode) support. Enables NDEF read/write, fast data transfer, and tag discovery for STMicroelectronics ST25 series NFC tags.

## Platform Support

| Platform | Support |
|----------|---------|
| Android  | Full support (ST25SDK v1.10.0) |
| iOS      | Full support (ST25SDK + CoreNFC, iOS 14.1+) |

## Prerequisites

### Android

- Minimum SDK: 21 / Compile SDK: 34
- Requires `st25sdk-1.10.0.jar` placed in `android/libs/`
- Add to `android/app/build.gradle`:
  ```groovy
  dependencies {
      implementation 'com.madgag.spongycastle:bcpkix-jdk15on:1.58.0.0'
      implementation 'org.apache.commons:commons-lang3:3.5'
  }
  ```

### iOS

- Minimum iOS: 14.1
- Requires NFC capability with following entitlements:
  ```xml
  <key>com.apple.developer.nfc.readersession.formats</key>
  <array>
      <string>NDEF</string>
      <string>TAG</string>
  </array>
  ```
- Add `NFCReaderUsageDescription` to Info.plist:
  ```xml
  <key>NFCReaderUsageDescription</key>
  <string>This app uses NFC to communicate with ST25 NFC tags.</string>
  ```

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nfc_ftm:
    path: /path/to/nfc_ftm
```

## Usage

### Basic Setup

```dart
import 'package:nfc_ftm/nfc_ftm.dart';

final nfcFtm = NfcFtm();

// Check if NFC is available
bool available = await nfcFtm.isAvailable();

// Get current NFC state
NfcState state = await nfcFtm.getNfcState();
```

### Tag Discovery

```dart
// Open NFC in NDEF mode — discovers any NFC tag
await nfcFtm.openNFC((NfcTag tag) {
  print('Tag discovered: ${tag.id}');
  print('Technologies: ${tag.type}');
  print('Memory size: ${tag.memSize} bytes');
  print('NDEF length: ${tag.tagNDEFLength}');
});

// Open NFC in FTM mode — discovers ST25DV tags and initializes FTM
await nfcFtm.openFTM((NfcTag tag) {
  print('FTM Tag discovered: ${tag.id}');

  // Initialize FTM commands
  bool ftmReady = await nfcFtm.getFTM();
  if (ftmReady) {
    print('FTM ready');
  }
});

// Close NFC session
await nfcFtm.closeNFC();
```

### FTM Data Transfer

> **Note**: FTM requires an **ST25DV-I2C** or **ST25DV-PWM** tag with mailbox support. Other tag types will report `NO_FTM_MODE`.

```dart
// Send data via FTM and receive response
List<int> dataToSend = utf8.encode('{"cmd":"read_sensor","id":1}');

List<int> response = await nfcFtm.sendFTMData(
  dataToSend,
  transmissionProgress: (transmittedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('Tx: $secondaryProgress% ($transmittedBytes/$totalSize bytes)');
  },
  receptionProgress: (receivedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('Rx: $secondaryProgress% ($receivedBytes/$totalSize bytes)');
  },
);

print('Response: ${utf8.decode(response)}');

// Read data from tag via FTM (uses FTM_CMD_READ_DATA)
List<int> cmdData = utf8.encode('{"cmd":"get_data"}');
List<int> result = await nfcFtm.readFTMData(cmdData);

// Cancel ongoing transfer
nfcFtm.cancelTransfer();
```

### NDEF Read/Write

```dart
// Read NDEF text message from tag
NdefTag? ndef = await nfcFtm.readNdefTag();
if (ndef != null) {
  print('Language: ${ndef.language}');
  print('Data: ${ndef.data}');
}

// Write NDEF text record to tag
bool success = await nfcFtm.writeNdefTag('Hello NFC');
```

### Toast/Status Stream

```dart
nfcFtm.getToastStream().listen((message) {
  // Messages: "isEnabledNFC: true", "NO_FTM_MODE", "FTM init OK",
  // "write NDEF success", "NFC read cancelled.", etc.
  print('NFC: $message');
});
```

## API Reference

### NfcFtm

| Method | Returns | Description |
|--------|---------|-------------|
| `isAvailable()` | `Future<bool>` | Check if NFC hardware is available |
| `getNfcState()` | `Future<NfcState>` | Get current NFC state |
| `openNFC(onDiscovered)` | `Future<bool>` | Start NFC session (NDEF mode), callback on tag found |
| `openFTM(onDiscovered)` | `Future<bool>` | Start NFC session (FTM mode), callback on ST25DV tag found |
| `closeNFC()` | `Future<bool>` | Close current NFC session |
| `getFTM()` | `Future<bool>` | Initialize FTM commands. Returns `true` when FTM ready |
| `sendFTMData(data, {tx, rx})` | `Future<List<int>>` | Send data via FTM, returns tag response |
| `readFTMData(data)` | `Future<List<int>>` | Read data from tag via FTM |
| `cancelTransfer()` | `void` | Cancel ongoing FTM transfer |
| `readNdefTag()` | `Future<NdefTag?>` | Read NDEF text message from tag |
| `writeNdefTag(text)` | `Future<bool>` | Write NDEF text record to tag |
| `getToastStream()` | `Stream<String>` | Status message stream |
| `dispose()` | `Future<void>` | Clean up resources |

### NfcState

```dart
enum NfcState {
  noAvailable,       // -1: NFC hardware not found
  disabled,          //  0: NFC idle
  enabled,           //  1: NFC session started
  readTag,           //  2: Tag detected
  modeFTMnoCommand,  //  3: FTM mode, tag found, commands not initialized
  modeFTM,           //  4: FTM mode active, commands ready
}
```

### NfcTag

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Tag UID (hex string) |
| `type` | `List<String>` | Supported tag technologies (e.g., `NfcV`, `IsoDep`, `NfcA`) |
| `memSize` | `int?` | Memory size in bytes (ST25DV only) |
| `tagNDEFLength` | `int?` | NDEF message length in bytes |

### NdefTag

| Field | Type | Description |
|-------|------|-------------|
| `language` | `String` | Language code (e.g. "en") |
| `data` | `String` | Decoded text content |
| `payload` | `List<int>` | Raw NDEF payload bytes |

### Callbacks

```dart
/// Tag discovery callback — called when a tag is detected
typedef NfcTagCallback = void Function(NfcTag tag);

/// Transmission progress — called during FTM send
typedef TransmissionProgress = void Function(
  int transmittedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

/// Reception progress — called during FTM receive
typedef ReceptionProgress = void Function(
  int receivedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);
```

## Tags

| Tag Series | NDEF | FTM | Notes |
|------------|------|-----|-------|
| ST25DV-I2C (ST25DV04K/16K/64K) | ✅ | ✅ | Mailbox size: 256 bytes |
| ST25DV-PWM (ST25DV02K-W1/W2) | ✅ | ✅ | Mailbox size: 256 bytes |
| ST25DVC (ST25DV04KC/16KC/64KC) | ✅ | ✅ | Mailbox size: 256 bytes |
| ST25TV (ST25TVxxx) | ✅ | ❌ | No mailbox support |
| NXP NTAG / ICODE | ✅ | ❌ | NDEF only |
| Other ISO15693 (NfcV) | ✅ | ❌ | NDEF via native API |

## License

This project is a proprietary Flutter plugin.
