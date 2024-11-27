typedef NfcTagCallback = Future<void> Function(NfcTag tag);

// 发送数据的进度回调
typedef TransmissionProgress = Future<void> Function(
  int transmittedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

// 接收数据的进度回调
typedef ReceptionProgress = Future<void> Function(
  int receivedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

class NfcTag {
  const NfcTag({
    required this.id,
    required this.type,
    this.memSize,
    this.tagNDEFLength,
  });

  final String id;
  final List<String> type;
  final int? memSize;
  final int? tagNDEFLength;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type.join(", "),
      'memSize': memSize,
      'tagNDEFLength': tagNDEFLength,
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
    );
  }

  @override
  String toString() {
    return '{id: $id, type: $type, memSize: $memSize, tagNDEFLength: $tagNDEFLength}';
  }
}

class NdefTag {
  const NdefTag({
    required this.data,
    required this.payload,
  });

  final String data;
  final List<int> payload;

  Map<String, Object?> toJson() {
    return {
      'data': data,
      'payload': payload,
    };
  }

  factory NdefTag.fromMap(Map<String, Object?> map) {
    return NdefTag(
      data: map['data'] as String,
      payload: map['payload'] as List<int>,
    );
  }

  @override
  String toString() {
    return '{data: $data, payload: $payload}';
  }
}
