# nfc_ftm

Flutter plugin for ST25 NFC tags with FTM (Fast Transfer Mode) support. Enables NDEF read/write, fast data transfer, and tag discovery for STMicroelectronics ST25 series NFC tags.

## Platform Support

| Platform | Support |
|----------|---------|
| Android  | Full support (ST25SDK 1.10.0) |
| iOS      | Full support (CoreNFC, iOS 13+) |

## Prerequisites

### Android

- Minimum SDK: 21 / Compile SDK: 34
- Requires `st25sdk-1.10.0.jar` placed in `android/libs/`
- Add to `android/app/build.gradle`:
  ```groovy
  android {
      compileSdk = 34
  }
  ```

### iOS

- Minimum iOS: 13.0
- Requires NFC capability in Xcode project
- Add `NFCReaderUsageDescription` to Info.plist

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nfc_ftm:
    path: /path/to/nfc_ftm
```

## Usage

```dart
import 'package:nfc_ftm/nfc_ftm.dart';

final nfcFtm = NfcFtm();

// Check if NFC is available
bool available = await nfcFtm.isAvailable();

// Get current NFC state
NfcState state = await nfcFtm.getNfcState();

// Open NFC in NDEF mode
bool opened = await nfcFtm.openNFC((NfcTag tag) {
  print('Tag discovered: ${tag.id}');
});

// Open NFC in FTM (Fast Transfer Mode)
bool opened = await nfcFtm.openFTM((NfcTag tag) {
  print('FTM Tag discovered: ${tag.id}');
});

// Close NFC session
await nfcFtm.closeNFC();
```

### FTM Data Transfer

```dart
List<int> dataToSend = utf8.encode('Hello ST25');

List<int> response = await nfcFtm.sendFTMData(
  dataToSend,
  transmissionProgress: (transmittedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('Tx: $secondaryProgress%');
  },
  receptionProgress: (receivedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('Rx: $secondaryProgress%');
  },
);

// Cancel ongoing transfer
nfcFtm.cancelTransfer();
```

### NDEF Read/Write

```dart
// Read NDEF message from tag
NdefTag? ndef = await nfcFtm.readNdefTag();
if (ndef != null) {
  print('Language: ${ndef.language}');
  print('Data: ${ndef.data}');
}

// Write NDEF text record
bool success = await nfcFtm.writeNdefTag('Hello NFC');
```

### Toast Stream

```dart
nfcFtm.getToastStream().listen((message) {
  print('NFC event: $message');
});
```

## API Reference

### NfcFtm

| Method | Returns | Description |
|--------|---------|-------------|
| `isAvailable()` | `Future<bool>` | Check if NFC hardware is available |
| `getNfcState()` | `Future<NfcState>` | Get current NFC adapter state |
| `openNFC(onDiscovered)` | `Future<bool>` | Start NFC session in NDEF mode |
| `openFTM(onDiscovered)` | `Future<bool>` | Start NFC session in FTM mode |
| `closeNFC()` | `Future<bool>` | Close current NFC session |
| `getFTM()` | `Future<bool>` | Initialize FTM commands on tag |
| `sendFTMData(data, {progress})` | `Future<List<int>>` | Send data via FTM, returns response |
| `readFTMData(data, {progress})` | `Future<List<int>>` | Read data via FTM with command |
| `cancelTransfer()` | `void` | Cancel ongoing FTM transfer |
| `readNdefTag()` | `Future<NdefTag?>` | Read NDEF message from tag |
| `writeNdefTag(data)` | `Future<bool>` | Write NDEF text record |
| `getToastStream()` | `Stream<String>` | Stream of NFC status messages |
| `dispose()` | `Future<void>` | Clean up resources |

### NfcState

```dart
enum NfcState {
  noAvailable,       // NFC hardware not found
  disabled,          // NFC is turned off
  enabled,           // NFC is turned on
  readTag,           // Tag detected
  modeFTMnoCommand,  // FTM mode, commands not initialized
  modeFTM,           // FTM mode active
}
```

### NfcTag

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Tag UID |
| `type` | `List<String>` | Supported tag technologies |
| `memSize` | `int?` | Memory size in bytes |
| `tagNDEFLength` | `int?` | NDEF message length |

### NdefTag

| Field | Type | Description |
|-------|------|-------------|
| `language` | `String` | Language code (e.g. "en") |
| `data` | `String` | Decoded text content |
| `payload` | `List<int>` | Raw NDEF payload bytes |

### Callbacks

```dart
// Tag discovery callback
typedef NfcTagCallback = Future<void> Function(NfcTag tag);

// Data transmission progress
typedef TransmissionProgress = void Function(
  int transmittedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,           // 0-100
  int secondaryProgress,  // 0-100
);

// Data reception progress
typedef ReceptionProgress = void Function(
  int receivedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,           // 0-100
  int secondaryProgress,  // 0-100
);
```

## License

This project is a proprietary Flutter plugin.
