import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_ftm/nfc_ftm.dart';
import 'package:nfc_ftm/nfc_ftm_method_channel.dart';
import 'package:nfc_ftm/nfc_ftm_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNfcFtmPlatform
    with MockPlatformInterfaceMixin
    implements NfcFtmPlatform {
  @override
  Future<NdefTag?> readNdefTag() => Future.value(
        const NdefTag(
          language: "",
          data: "",
          payload: [],
        ),
      );

  @override
  Future<bool> isAvailable() => Future.value(false);

  @override
  Future<NfcState> getNfcState() => Future.value(NfcState.noAvailable);

  @override
  Future<bool> openNFC(NfcTagCallback onDiscovered) => Future.value(false);

  @override
  Future<bool> openFTM(NfcTagCallback onDiscovered) => Future.value(false);

  @override
  Future<bool> closeNFC() => Future.value(false);

  @override
  Future<bool> getFTM() => Future.value(false);

  @override
  Stream<String> getToastStream() {
    return Stream.fromIterable(['value']);
  }

  @override
  void reopenToastStream() {
    throw UnimplementedError();
  }

  @override
  void closeToastStream() {}

  @override
  NfcTagCallback? onDiscovered;

  @override
  Future<void> dispose() {
    throw UnimplementedError();
  }

  @override
  Future<List<int>> readFTMData(List<int> data,
      {TransmissionProgress? tProgress, ReceptionProgress? rProgress}) {
    throw UnimplementedError();
  }

  @override
  Future<List<int>> sendFTMData(List<int> data,
      {TransmissionProgress? tProgress, ReceptionProgress? rProgress}) {
    throw UnimplementedError();
  }

  @override
  Future<bool> writeNdefTag(String data) {
    throw UnimplementedError();
  }
}

void main() {
  final NfcFtmPlatform initialPlatform = NfcFtmPlatform.instance;

  test('$MethodChannelNfcFtm is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelNfcFtm>());
  });
}
