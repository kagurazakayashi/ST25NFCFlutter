import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'nfc_ftm_method_channel.dart';
import 'nfc_obj.dart';

abstract class NfcFtmPlatform extends PlatformInterface {
  /// Constructs a NfcFtmPlatform.
  NfcFtmPlatform() : super(token: _token);

  static final Object _token = Object();

  static NfcFtmPlatform _instance = MethodChannelNfcFtm();

  /// The default instance of [NfcFtmPlatform] to use.
  ///
  /// Defaults to [MethodChannelNfcFtm].
  static NfcFtmPlatform get instance => _instance;

  NfcTagCallback? onDiscovered;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NfcFtmPlatform] when
  /// they register themselves.
  static set instance(NfcFtmPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> isAvailable() {
    throw UnimplementedError('isAvailable() has not been implemented.');
  }

  Future<NfcState> getNfcState() {
    throw UnimplementedError('getNfcState() has not been implemented.');
  }

  Future<bool> openNFC(NfcTagCallback onDiscovered) {
    throw UnimplementedError('openNFC() has not been implemented.');
  }

  Future<bool> openFTM(NfcTagCallback onDiscovered) {
    throw UnimplementedError('openFTM() has not been implemented.');
  }

  Future<bool> closeNFC() {
    throw UnimplementedError('closeNFC() has not been implemented.');
  }

  Future<bool> getFTM() {
    throw UnimplementedError('getFTM() has not been implemented.');
  }

  Future<List<int>> sendFTMData(
    List<int> data, {
    TransmissionProgress? tProgress,
    ReceptionProgress? rProgress,
  }) async {
    throw UnimplementedError('sendFTMData() has not been implemented.');
  }

  Future<List<int>> readFTMData(
    List<int> data, {
    TransmissionProgress? tProgress,
    ReceptionProgress? rProgress,
  }) async {
    throw UnimplementedError('readFTMData() has not been implemented.');
  }

  Future<NdefTag> readNdefTag() {
    throw UnimplementedError('readNdefTag() has not been implemented.');
  }

  Future<bool> writeNdefTag(String data){
    throw UnimplementedError('writeNdefTag() has not been implemented.');
  }

  Stream<String> getToastStream() {
    throw UnimplementedError('getToastStream() has not been implemented.');
  }

  void reopenToastStream(){
    throw UnimplementedError('reopenToastStream() has not been implemented.');
  }

  void closeToastStream() {
    throw UnimplementedError('closeToastStream() has not been implemented.');
  }

  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }

  // // 抽象方法，返回一个数据流
  // Stream<Map> getDataStream(){
  //   throw UnimplementedError('getDataStream() has not been implemented.');
  // }
}
