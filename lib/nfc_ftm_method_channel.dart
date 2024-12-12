import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'nfc_ftm_platform_interface.dart';
import 'nfc_obj.dart';

/// An implementation of [NfcFtmPlatform] that uses method channels.
class MethodChannelNfcFtm extends NfcFtmPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  // 向原生发送通知，原生可以回复该通知
  final MethodChannel methodChannel = const MethodChannel('nfc_ftm_to_native');
  // 接收原生随时发送的通知
  final EventChannel eventChannel = const EventChannel('nfc_ftm_to_flutter');

  // Stream<Map>? stream;
  late StreamController<String> toastController;
  late Stream<String> toastStream;

  // static StreamController<String>

  NfcTagCallback? nfcTagCallback;
  TransmissionProgress? transmissionProgress;
  ReceptionProgress? receptionProgress;

  MethodChannelNfcFtm() {
    initToastStream();
    eventChannel.receiveBroadcastStream().listen((event) {
      print('>>>event: $event');
      if (event.runtimeType.toString() != "_Map<Object?, Object?>") {
        return;
      }
      switch (event['k']) {
        case "onDiscovered":
          if (event is Map) {
            final mapevent = Map<String, Object>.from(event);
            final tag = $GetNfcTag(mapevent);
            if (nfcTagCallback != null) {
              nfcTagCallback!(tag);
            }
          } else {
            throw ArgumentError('Unexpected event format: $event');
          }
          break;
        case "toast":
          reopenToastStream();
          toastController.add(event['v'] as String);
          break;
        case "transmissionProgress":
          if (event is Map) {
            final mapevent = Map<String, Object>.from(event);
            final progress = mapevent['progress'] as int;
            final secondaryProgress = mapevent['secondaryProgress'] as int;
            final transmittedBytes = mapevent['transmittedBytes'] as int;
            final acknowledgedBytes = mapevent['acknowledgedBytes'] as int;
            final totalSize = mapevent['totalSize'] as int;
            if (transmissionProgress != null) {
              transmissionProgress!(
                transmittedBytes,
                acknowledgedBytes,
                totalSize,
                progress,
                secondaryProgress,
              );
            }
          }
          break;
        case "receptionProgress":
          if (event is Map) {
            final mapevent = Map<String, Object>.from(event);
            final progress = mapevent['progress'] as int;
            final secondaryProgress = mapevent['secondaryProgress'] as int;
            final receivedBytes = mapevent['receivedBytes'] as int;
            final acknowledgedBytes = mapevent['acknowledgedBytes'] as int;
            final totalSize = mapevent['totalSize'] as int;
            if (receptionProgress != null) {
              receptionProgress!(
                receivedBytes,
                acknowledgedBytes,
                totalSize,
                progress,
                secondaryProgress,
              );
            }
          }
        default:
      }
    });
  }

  @override
  Future<void> dispose() async {
    methodChannel.invokeMethod<bool>('closeNFC');
    toastController.close();
  }

  @override
  Future<bool> isAvailable() async {
    final result = await methodChannel.invokeMethod<bool>('isAvailable');
    return result ?? false;
  }

  @override
  Future<NfcState> getNfcState() async {
    final result = await methodChannel.invokeMethod<int>('state');
    switch (result) {
      case -1:
        return NfcState.noAvailable;
      case 0:
        return NfcState.disabled;
      case 1:
        return NfcState.enabled;
      case 2:
        return NfcState.readTag;
      case 3:
        return NfcState.modeFTMnoCommand;
      case 4:
        return NfcState.modeFTM;
      default:
        return NfcState.noAvailable;
    }
  }

  @override
  Future<bool> openNFC(NfcTagCallback onDiscovered) async {
    nfcTagCallback = onDiscovered;
    final result = await methodChannel.invokeMethod<bool>('openNFC');
    return result ?? false;
  }

  @override
  Future<bool> openFTM(NfcTagCallback onDiscovered) async {
    nfcTagCallback = onDiscovered;
    final result = await methodChannel.invokeMethod<bool>('openFTM');
    return result ?? false;
  }

  @override
  Future<bool> closeNFC() async {
    final result = await methodChannel.invokeMethod<bool>('closeNFC');
    return result ?? false;
  }

  @override
  Future<bool> getFTM() async {
    final result = await methodChannel.invokeMethod<bool>('getFTM');
    return result ?? false;
  }

  @override
  Future<List<int>> sendFTMData(
    List<int> data, {
    TransmissionProgress? tProgress,
    ReceptionProgress? rProgress,
  }) async {
    transmissionProgress = tProgress;
    receptionProgress = rProgress;
    final result = await methodChannel.invokeMethod<List<int>>(
      'sendFTMData',
      {'data': data},
    );
    return result ?? List<int>.empty();
  }

  @override
  Future<List<int>> readFTMData(
    List<int> data, {
    TransmissionProgress? tProgress,
    ReceptionProgress? rProgress,
  }) async {
    transmissionProgress = tProgress;
    receptionProgress = rProgress;
    final result = await methodChannel.invokeMethod<List<int>>(
      'readFTMData',
      {'data': data},
    );
    return result ?? List<int>.empty();
  }

  @override
  Future<NdefTag?> readNdefTag() async {
    final result = await methodChannel.invokeMethod<Map>('NDEF@read');
    if (result == null) {
      return null;
    }
    String lang = "";
    String data = "";
    List<int> payload = [];
    if (result.containsKey('lang')) {
      lang = result['lang'] as String;
    }
    if (result.containsKey('data')) {
      data = result['data'] as String;
    }
    if (result.containsKey('payload')) {
      payload = result['payload'] as List<int>;
    }
    return NdefTag(
      language: lang,
      data: data,
      payload: payload,
    );
  }

  @override
  Future<bool> writeNdefTag(String data) async {
    final result = await methodChannel.invokeMethod<bool>(
      'NDEF@write',
      {'data': data},
    );
    return result ?? false;
  }

  void initToastStream() {
    toastController = StreamController<String>.broadcast();
    toastStream = toastController.stream.asBroadcastStream();
  }

  @override
  Stream<String> getToastStream() {
    reopenToastStream();
    return toastStream;
  }

  @override
  void reopenToastStream() {
    if (toastController.isClosed) {
      initToastStream();
    }
  }

  @override
  void closeToastStream() {
    toastController.close();
  }
}

NfcTag $GetNfcTag(Map<String, Object> map) {
  String techListString = (map['type'] as String);
  List<String> techList = techListString
      .substring(1, techListString.length - 1) // 去除两边的方括号
      .split(", ") // 按逗号分隔
      .toList();
  return NfcTag(
    id: map['id'] as String,
    type: techList,
    memSize: map['memSize'] as int?,
    tagNDEFLength: map['ndefLength'] as int?,
  );
}
