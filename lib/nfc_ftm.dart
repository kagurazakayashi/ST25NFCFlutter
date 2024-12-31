import 'nfc_ftm_platform_interface.dart';
import 'nfc_obj.dart';
export 'nfc_obj.dart';

class NfcFtm {
  Future<bool> isAvailable() {
    return NfcFtmPlatform.instance.isAvailable();
  }

  Future<NfcState> getNfcState() {
    return NfcFtmPlatform.instance.getNfcState();
  }

  Future<bool> openNFC(NfcTagCallback onDiscovered) {
    return NfcFtmPlatform.instance.openNFC(onDiscovered);
  }

  Future<bool> openFTM(NfcTagCallback onDiscovered) {
    return NfcFtmPlatform.instance.openFTM(onDiscovered);
  }

  Future<bool> closeNFC() {
    return NfcFtmPlatform.instance.closeNFC();
  }

  Future<bool> getFTM() {
    return NfcFtmPlatform.instance.getFTM();
  }

  /// Sends FTM data to the NFC tag.
  ///
  /// This method sends the provided [data] to the NFC tag and optionally
  /// reports the transmission and reception progress.
  ///
  /// The [data] parameter is a list of integers representing the data to be sent.
  ///
  /// The [transmissionProgress] callback, if provided, will be called with the
  /// progress of the data transmission. The callback parameters are:
  /// - [transmittedBytes]: The number of bytes transmitted so far.
  /// - [acknowledgedBytes]: The number of bytes acknowledged so far.
  /// - [totalSize]: The total size of the data being transmitted.
  /// - [progress]: The overall progress percentage.
  /// - [secondaryProgress]: The secondary progress percentage.
  ///
  /// The [receptionProgress] callback, if provided, will be called with the
  /// progress of the data reception. The callback parameters are:
  /// - [transmittedBytes]: The number of bytes transmitted so far.
  /// - [acknowledgedBytes]: The number of bytes acknowledged so far.
  /// - [totalSize]: The total size of the data being received.
  /// - [progress]: The overall progress percentage.
  /// - [secondaryProgress]: The secondary progress percentage.
  ///
  /// Returns a [Future] that completes with a list of integers representing
  /// the received data.
  ///
  /// Example usage:
  /// ```dart
  /// List<int> dataToSend = [0x01, 0x02, 0x03];
  /// List<int> receivedData = await sendFTMData(
  ///   dataToSend,
  ///   transmissionProgress: (transmittedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
  ///     print('Transmission progress: $secondaryProgress%');
  ///   },
  ///   receptionProgress: (transmittedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
  ///     print('Reception progress: $secondaryProgress%');
  ///   },
  /// );
  /// print('Received data: $receivedData');
  /// ```
  ///
  /// Throws an [Exception] if there is an error during the transmission or reception.
  Future<List<int>> sendFTMData(
    List<int> data, {
    TransmissionProgress? transmissionProgress,
    ReceptionProgress? receptionProgress,
  }) async {
    return NfcFtmPlatform.instance.sendFTMData(
      data,
      tProgress: transmissionProgress,
      rProgress: receptionProgress,
    );
  }

  Future<List<int>> readFTMData(
    List<int> data, {
    TransmissionProgress? transmissionProgress,
    ReceptionProgress? receptionProgress,
  }) async {
    return NfcFtmPlatform.instance.readFTMData(
      data,
      tProgress: transmissionProgress,
      rProgress: receptionProgress,
    );
  }

  void cancelTransfer(){
    return NfcFtmPlatform.instance.cancelTransfer();
  }

  Future<NdefTag?> readNdefTag() {
    return NfcFtmPlatform.instance.readNdefTag();
  }

  Future<bool> writeNdefTag(String data) {
    return NfcFtmPlatform.instance.writeNdefTag(data);
  }

  Stream<String> getToastStream() {
    return NfcFtmPlatform.instance.getToastStream();
  }

  void reopenToastStream({String streamName = 'toast'}) {
    return NfcFtmPlatform.instance.reopenToastStream(streamName: streamName);
  }

  void closeToastStream({String streamName = 'toast'}) {
    return NfcFtmPlatform.instance.closeToastStream(streamName: streamName);
  }

  Future<void> dispose() async {
    return NfcFtmPlatform.instance.dispose();
  }
}
