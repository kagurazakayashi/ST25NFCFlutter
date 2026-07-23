typedef NfcTagCallback = Future<void> Function(NfcTag tag);

// 发送数据的进度回调
typedef TransmissionProgress = void Function(
  int transmittedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

// 接收数据的进度回调
typedef ReceptionProgress = void Function(
  int receivedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

enum NfcState {
  noAvailable, // 未找到 NFC
  disabled, // NFC 关闭
  enabled, // NFC 打开
  readTag, // 读取到标签
  modeFTMnoCommand, // FTM 模式，为初始化FtmCommands
  modeFTM, // FTM 模式
}

class NfcTag {
  const NfcTag({
    required this.id,
    required this.type,
    this.memSize,
    this.tagNDEFLength,
    this.ndefText,
    this.ndefLang,
    this.ndefPayload,
    this.isFTMmode,
  });

  final String id;
  final List<String> type;
  final int? memSize;
  final int? tagNDEFLength;
  final String? ndefText;
  final String? ndefLang;
  final List<int>? ndefPayload;
  final bool? isFTMmode;

  NdefTag? get ndefTag {
    if (ndefText == null || ndefText!.isEmpty) return null;
    return NdefTag(
      language: ndefLang ?? "",
      data: ndefText!,
      payload: ndefPayload ?? [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.join(", "),
      'memSize': memSize,
      'tagNDEFLength': tagNDEFLength,
      'isFTMmode': isFTMmode,
    };
  }

  factory NfcTag.fromMap(Map<String, Object?> map) {
    return NfcTag(
      id: map['id'] as String,
      type: (map['type'] as String)
          .substring(1, (map['type'] as String).length - 1)
          .split(", ")
          .toList(),
      memSize: map['memSize'] as int?,
      isFTMmode: map['isFTMmode'] as bool?,
    );
  }

  @override
  String toString() {
    return '{id: $id, type: $type, memSize: $memSize, tagNDEFLength: $tagNDEFLength, isFTMmode: $isFTMmode}';
  }
}

class NdefTag {
  const NdefTag({
    required this.language,
    required this.data,
    required this.payload,
  });

  final String language;
  final String data;
  final List<int> payload;

  Map<String, Object?> toJson() {
    return {
      'language': language,
      'data': data,
      'payload': payload,
    };
  }

  factory NdefTag.fromMap(Map<String, Object?> map) {
    return NdefTag(
      language: map['language'] as String,
      data: map['data'] as String,
      payload: map['payload'] as List<int>,
    );
  }

  @override
  String toString() {
    return '{language: $language, data: $data, payload: $payload}';
  }
}
