import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// import 'package:nfc_ftm/nfc_ftm_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // MethodChannelNfcFtm platform = MethodChannelNfcFtm();
  const MethodChannel channel = MethodChannel('nfc_ftm');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

}
