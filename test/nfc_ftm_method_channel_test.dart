import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_ftm/nfc_ftm_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('nfc_ftm_to_native');
  final MethodChannelNfcFtm platform = MethodChannelNfcFtm();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('readNdefTag', () {
    test('returns null when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async => null,
      );

      final result = await platform.readNdefTag();
      expect(result, isNull);
    });

    test('returns null when native returns empty map', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async => <String, dynamic>{},
      );

      final result = await platform.readNdefTag();
      expect(result, isNull);
    });

    test('returns null when NDEF data is empty string', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async => <String, dynamic>{
          'lang': 'en',
          'data': '',
          'payload': <int>[],
        },
      );

      final result = await platform.readNdefTag();
      expect(result, isNull);
    });

    test('returns NdefTag when NDEF has valid data', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async => <String, dynamic>{
          'lang': 'en',
          'data': 'Hello NFC',
          'payload': const <int>[2, 101, 110, 72, 101, 108, 108, 111, 32, 78, 70, 67],
        },
      );

      final result = await platform.readNdefTag();
      expect(result, isNotNull);
      expect(result!.language, 'en');
      expect(result.data, 'Hello NFC');
      expect(result.payload, isNotEmpty);
    });
  });
}
