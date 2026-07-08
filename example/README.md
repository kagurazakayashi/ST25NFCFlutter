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
