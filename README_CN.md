# nfc_ftm

适用于 ST25 NFC 标签的 Flutter 插件，支持 FTM（快速传输模式）。可为 STMicroelectronics ST25 系列 NFC 标签提供 NDEF 读写、快速数据传输及标签发现功能。

## 平台支持

| 平台    | 支持情况 |
|---------|----------|
| Android | 完整支持（ST25SDK v1.10.0） |
| iOS     | 完整支持（ST25SDK + CoreNFC，iOS 14.1+） |

## 前置条件

### Android

- 最低 SDK: 21 / 编译 SDK: 34
- 需将 `st25sdk-1.10.0.jar` 放置于 `android/libs/`
- 在 `android/app/build.gradle` 中添加：
  ```groovy
  dependencies {
      implementation 'com.madgag.spongycastle:bcpkix-jdk15on:1.58.0.0'
      implementation 'org.apache.commons:commons-lang3:3.5'
  }
  ```

### iOS

- 最低 iOS: 14.1
- 需开启 NFC 能力并配置以下 entitlements：
  ```xml
  <key>com.apple.developer.nfc.readersession.formats</key>
  <array>
      <string>NDEF</string>
      <string>TAG</string>
  </array>
  ```
- 在 Info.plist 中添加 `NFCReaderUsageDescription`：
  ```xml
  <key>NFCReaderUsageDescription</key>
  <string>此应用使用 NFC 与 ST25 NFC 标签通信。</string>
  ```

## 安装

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  nfc_ftm:
    path: /path/to/nfc_ftm
```

## 使用方法

### 基础设置

```dart
import 'package:nfc_ftm/nfc_ftm.dart';

final nfcFtm = NfcFtm();

// 检查 NFC 是否可用
bool available = await nfcFtm.isAvailable();

// 获取当前 NFC 状态
NfcState state = await nfcFtm.getNfcState();
```

### 标签发现

`onDiscovered` 回调不仅在标签首次被检测到时触发，也会在每次操作完成后再次触发
（`getFTM`、`sendFTMData`、`readFTMData`、`readNdefTag`、`writeNdefTag`），提供最新的标签状态。

```dart
NfcTag? currentTag;

// 以 FTM 模式打开 NFC — 发现 ST25DV 标签并初始化 FTM
// alertMessage（仅 iOS）：自定义 NFC 系统弹窗文字
await nfcFtm.openFTM((NfcTag tag) {
  currentTag = tag;

  // isFTMmode: true 时表示标签的 mailbox 已启用（FTM 模式）
  //            false 时表示标签为 NDEF 模式或非 ST25DV 标签
  if (tag.isFTMmode == true) {
    print('FTM 模式标签，内存: ${tag.memSize} bytes');

    // 初始化 FTM 命令（也会触发 onDiscovered 回调）
    bool ftmReady = await nfcFtm.getFTM();
    if (ftmReady) {
      print('FTM 就绪');
    }
  } else {
    print('NDEF 模式标签');
    // 从标签读取 NDEF 数据（也会触发 onDiscovered 回调）
    NdefTag? ndef = await nfcFtm.readNdefTag();
    if (ndef != null) {
      print('NDEF 数据: ${ndef.data}');
    }
  }
});

// 每次 FTM 传输完成后 onDiscovered 回调会再次触发，
// 将 currentTag 更新为最新标签状态
List<int> response = await nfcFtm.sendFTMData(data);
// currentTag.isFTMmode 反映了传输完成后的标签状态

// 以 NDEF 模式打开 NFC — 发现任意 NFC 标签
await nfcFtm.openNFC((NfcTag tag) {
  print('发现标签: ${tag.id}');
  print('技术: ${tag.type}');
  print('内存大小: ${tag.memSize} bytes');
  print('NDEF 长度: ${tag.tagNDEFLength}');
});

// 关闭 NFC 会话
await nfcFtm.closeNFC();
```

### FTM 数据传输

> **注意**：FTM 需要 **ST25DV-I2C** 或 **ST25DV-PWM** 标签，并支持 mailbox。其他标签类型将报告 `NO_FTM_MODE`。

> **注意（仅 iOS）**：`alertMessage` 参数用于自定义 NFC 系统弹窗文字。未指定时默认为 `"Hold smartphone near NFC tag"`。

```dart
// 通过 FTM 发送数据并接收响应
List<int> dataToSend = utf8.encode('{"cmd":"read_sensor","id":1}');

List<int> response = await nfcFtm.sendFTMData(
  dataToSend,
  transmissionProgress: (transmittedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('发送: $secondaryProgress% ($transmittedBytes/$totalSize bytes)');
  },
  receptionProgress: (receivedBytes, acknowledgedBytes, totalSize, progress, secondaryProgress) {
    print('接收: $secondaryProgress% ($receivedBytes/$totalSize bytes)');
  },
);

print('响应: ${utf8.decode(response)}');

// 通过 FTM 从标签读取数据（使用 FTM_CMD_READ_DATA）
List<int> cmdData = utf8.encode('{"cmd":"get_data"}');
List<int> result = await nfcFtm.readFTMData(cmdData);

// 取消正在进行的传输
nfcFtm.cancelTransfer();
```

### NDEF 读写

```dart
// 从标签读取 NDEF 文字消息
NdefTag? ndef = await nfcFtm.readNdefTag();
if (ndef != null) {
  print('语言: ${ndef.language}');
  print('数据: ${ndef.data}');
}

// 向标签写入 NDEF 文字记录
bool success = await nfcFtm.writeNdefTag('你好 NFC');
```

### Toast / 状态流

```dart
nfcFtm.getToastStream().listen((message) {
  // 消息示例: "isEnabledNFC: true", "NO_FTM_MODE", "FTM init OK",
  // "write NDEF success", "NFC read cancelled." 等
  print('NFC: $message');
});
```

## API 参考

### NfcFtm

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `isAvailable()` | `Future<bool>` | 检查 NFC 硬件是否可用 |
| `getNfcState()` | `Future<NfcState>` | 获取当前 NFC 状态 |
| `openNFC(onDiscovered, {alertMessage})` | `Future<bool>` | 启动 NFC 会话（NDEF 模式）。回调在标签发现时以及每次 NDEF/FTM 操作完成后触发，包含当前标签信息。`alertMessage` 自定义 NFC 弹窗文字（仅 iOS）。 |
| `openFTM(onDiscovered, {alertMessage})` | `Future<bool>` | 启动 NFC 会话（FTM 模式）。回调在标签发现时以及每次 NDEF/FTM 操作完成后触发，包含 `isFTMmode` 及当前标签信息。`alertMessage` 自定义 NFC 弹窗文字（仅 iOS）。 |
| `closeNFC()` | `Future<bool>` | 关闭当前 NFC 会话 |
| `getFTM()` | `Future<bool>` | 初始化 FTM 命令。FTM 就绪时返回 `true` |
| `sendFTMData(data, {tx, rx, alertMessage})` | `Future<List<int>>` | 通过 FTM 发送数据，返回标签响应。`alertMessage`（仅 iOS）。 |
| `readFTMData(data, {tProgress, rProgress, alertMessage})` | `Future<List<int>>` | 通过 FTM 从标签读取数据。`alertMessage`（仅 iOS）。 |
| `cancelTransfer()` | `void` | 取消正在进行的 FTM 传输 |
| `readNdefTag({alertMessage})` | `Future<NdefTag?>` | 从标签读取 NDEF 文字消息。`alertMessage`（仅 iOS）。 |
| `writeNdefTag(text, {alertMessage})` | `Future<bool>` | 向标签写入 NDEF 文字记录。`alertMessage`（仅 iOS）。 |
| `getToastStream()` | `Stream<String>` | 状态消息流 |
| `dispose()` | `Future<void>` | 清理资源 |

### NfcState

```dart
enum NfcState {
  noAvailable,       // -1: 未找到 NFC 硬件
  disabled,          //  0: NFC 空闲
  enabled,           //  1: NFC 会话已启动
  readTag,           //  2: 已检测到标签
  modeFTMnoCommand,  //  3: FTM 模式，标签已发现，命令未初始化
  modeFTM,           //  4: FTM 模式已激活，命令就绪
}
```

### NfcTag

通过 `onDiscovered` 回调返回，在标签发现时和每次操作（`getFTM`、`sendFTMData`、
`readFTMData`、`readNdefTag`、`writeNdefTag`）完成后均可获取。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 标签 UID（十六进制字符串） |
| `type` | `List<String>` | 支持的标签技术（如 `NfcV`、`IsoDep`、`NfcA`） |
| `memSize` | `int?` | 内存大小（字节，仅 ST25DV） |
| `tagNDEFLength` | `int?` | NDEF 消息长度（字节） |
| `isFTMmode` | `bool?` | `true` 时表示标签为 ST25DV 且 mailbox 已启用（FTM 模式），`false` 时表示 NDEF 模式或非 ST25DV 标签。每次操作后更新。 |
| `ndefText` | `String?` | 解码后的 NDEF 文字内容（仅 iOS，FTM 发现时可用） |
| `ndefLang` | `String?` | NDEF 语言代码，如 "en"（仅 iOS，FTM 发现时可用） |
| `ndefPayload` | `List<int>?` | 原始 NDEF payload 字节（仅 iOS，FTM 发现时可用） |
| `ndefTag` | `NdefTag?` | NDEF 数据的便捷 getter（`ndefText` 为空时返回 null） |

### NdefTag

| 字段 | 类型 | 说明 |
|------|------|------|
| `language` | `String` | 语言代码（如 "en"） |
| `data` | `String` | 解码后的文字内容 |
| `payload` | `List<int>` | 原始 NDEF payload 字节 |

### 回调

```dart
/// 标签发现回调 — 检测到标签时调用
typedef NfcTagCallback = void Function(NfcTag tag);

/// 传输进度 — FTM 发送期间调用
typedef TransmissionProgress = void Function(
  int transmittedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);

/// 接收进度 — FTM 接收期间调用
typedef ReceptionProgress = void Function(
  int receivedBytes,
  int acknowledgedBytes,
  int totalSize,
  int progress,
  int secondaryProgress,
);
```

## 标签兼容性

| 标签系列 | NDEF | FTM | 备注 |
|----------|------|-----|------|
| ST25DV-I2C (ST25DV04K/16K/64K) | ✅ | ✅ | Mailbox 大小: 256 bytes |
| ST25DV-PWM (ST25DV02K-W1/W2) | ✅ | ✅ | Mailbox 大小: 256 bytes |
| ST25DVC (ST25DV04KC/16KC/64KC) | ✅ | ✅ | Mailbox 大小: 256 bytes |
| ST25TV (ST25TVxxx) | ✅ | ❌ | 不支持 mailbox |
| NXP NTAG / ICODE | ✅ | ❌ | 仅 NDEF |
| 其他 ISO15693 (NfcV) | ✅ | ❌ | 通过原生 API 读取 NDEF |

## License

本工程为私有 Flutter 插件。
