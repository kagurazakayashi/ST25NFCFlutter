import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:nfc_ftm/nfc_ftm.dart';

void main() {
  // 禁用所有 debugPrint 输出
  debugPrint = (String? message, {int? wrapWidth}) {};

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map platformVersion = {};
  final _nfcFtmPlugin = NfcFtm();

  bool isAvailable = false;

  bool isInitFTM = false;
  bool isInitNFC = false;

  String sendFTMDataResult = "";
  String sendNDEFDataResult = "";

  // static const platform = MethodChannel('moe.yashi.nfc_ftm_example/nfc');
  String nfcDataStr = "No NFC data scanned yet";

  double totalProgress = 0.0;
  double secProgress = 0.0;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    _nfcFtmPlugin.getToastStream().listen((event) {
      print("event = $event");
      if (event == "NO_FTM_MODE") {
        BotToast.showText(onlyOne: false, text: "当前NFC标签未开启FTM模式");
        _nfcFtmPlugin.readNdefTag().then((value) {
          if (value == null) {
            BotToast.showText(onlyOne: false, text: "读取失败");
            return;
          }
          print(">> readNdefTag: ${value.payload} => ${value.data}");
          sendNDEFDataResult = value.data;
          setState(() {});
        });
      } else {
        BotToast.showText(onlyOne: false, text: event);
      }
    });

    isAvailable = await _nfcFtmPlugin.isAvailable();

    // Listen for NFC data from the native code
    // platform.setMethodCallHandler((call) async {
    //   if (call.method == "onNfcScanned") {
    //     setState(() {
    //       _nfcData = call.arguments;
    //     });
    //     // Navigate to a different page if necessary
    //     Navigator.push(
    //       context,
    //       MaterialPageRoute(
    //           builder: (context) => NfcDetailPage(nfcData: _nfcData)),
    //     );
    //   }
    // });

    if (!mounted) return;

    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    _nfcFtmPlugin.closeNFC();
  }

  // 十六进制字符串转字节数组
  List<int> hexStringToBytes(String hexString) {
    List<int> bytes = [];
    for (int i = 0; i < hexString.length; i += 2) {
      String byteString = hexString.substring(i, i + 2);
      int byte = int.parse(byteString, radix: 16);
      bytes.add(byte);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
          backgroundColor: isInitNFC ? Colors.green : Colors.red,
          actions: [
            IconButton(
              icon: const Icon(Icons.autorenew_rounded),
              onPressed: () async {
                isAvailable = await _nfcFtmPlugin.isAvailable();
                setState(() {});
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            TextButton(
              onPressed: () async {
                isInitFTM = await _nfcFtmPlugin.openFTM((NfcTag tag) async {
                  print(">> openFTM: $tag");
                  String nfcStr = jsonEncode(tag);
                  print(">> nfcStr: $nfcStr");
                  // _nfcFtmPlugin.readNdefTag().then((value) {
                  //   print(">> readNdefTag: $value");
                  // });
                });
                setState(() {});
              },
              child: const Text("Open FTM"),
            ),
            Text(nfcDataStr),
            TextButton(
              onPressed: () async {
                isInitFTM = await _nfcFtmPlugin.getFTM();
              },
              child: const Text("Get FTM"),
            ),
            LinearProgressIndicator(
              value: totalProgress,
            ),
            LinearProgressIndicator(
              value: secProgress,
            ),
            TextButton(
              onPressed: !isInitFTM
                  ? null
                  : () async {
                      setState(() {
                        totalProgress = 0.0;
                        secProgress = 0.0;
                      });
                      String data = "{\"Rd\":[[-1,-65533],[1,3],5]}";
                      print(">> payload: ${utf8.encode(data)}");
                      
                      List<int> resultByte = await _nfcFtmPlugin
                          .sendFTMData(utf8.encode(data), receptionProgress: (
                        transmittedBytes,
                        acknowledgedBytes,
                        totalSize,
                        progress,
                        secondaryProgress,
                      ) {
                        setState(() {
                          totalProgress = progress / 100;
                          secProgress = secondaryProgress / 100;
                        });
                        print(">>>RRR: $progress % | $secondaryProgress %");
                        return Future.value();
                      });
                      sendFTMDataResult = utf8.decode(resultByte);
                      print(">>@@>> byte: $sendFTMDataResult");
                      setState(() {});
                    },
              child: const Text("Send FTM DATA"),
            ),
            Text("FTM Result: $sendFTMDataResult"),
            TextButton(
              onPressed: () async {
                await _nfcFtmPlugin.closeNFC();
                isInitNFC = await _nfcFtmPlugin.openNFC((NfcTag tag) async {
                  print(">> openNFC: $tag");
                  String nfcStr = jsonEncode(tag);
                  print(">> nfcStr: $nfcStr");
                  // _nfcFtmPlugin.readNdefTag().then((value) {
                  //   print(">> readNdefTag: $value");
                  // });
                });
                setState(() {});
              },
              child: const Text("Open NFC NDEF"),
            ),
            TextButton(
              onPressed: !isInitNFC
                  ? null
                  : () async {
                      _nfcFtmPlugin.readNdefTag().then((value) {
                        if (value == null) {
                          BotToast.showText(
                            onlyOne: false,
                            text: "读取失败",
                          );
                          return;
                        }
                        print(">>> $value");
                        List<int> header = value.payload.sublist(0, 1);
                        List<int> lang = value.payload.sublist(1, 3);
                        List<int> text = value.payload.sublist(3);

                        print(
                            ">> readNdefTag: ${value.payload} => ${value.data}");
                        print('>>> header: $header ${utf8.decode(header)}');
                        print('>>> language: $lang ${utf8.decode(lang)}');
                        print('>>> value: ${utf8.decode(text)}');
                        sendNDEFDataResult = value.data;
                        setState(() {});
                      });
                    },
              child: const Text("Read NDEF"),
            ),
            TextButton(
              onPressed: !isInitNFC
                  ? null
                  : () async {
// byte[] textBytes = text.getBytes(Charset.forName("UTF-8"));
// byte[] languageBytes = "en".getBytes(Charset.forName("US-ASCII"));
                      // List<int> payload = [];
                      String text = "[NDEF]测试 NFC 写入!@#dasf";
                      List<int> payload = utf8.encode(text);

                      // payload.addAll([2]);
                      // payload.addAll(utf8.encode("zh"));
                      // payload.addAll(utf8.encode(text));
                      print(
                          ">> payload: ${payload.length} ${payload.length + 7} $payload");
                      bool done = await _nfcFtmPlugin.writeNdefTag(text);
                      if (done) {
                        BotToast.showText(
                          onlyOne: false,
                          text: "写入成功",
                        );
                      } else {
                        BotToast.showText(
                          onlyOne: false,
                          text: "写入失败",
                        );
                      }
                    },
              child: const Text("Write NDEF"),
            ),
            Text("NDEF Result: $sendNDEFDataResult"),
            Text(platformVersion.toString()),
            Text("NFC: $isAvailable"),
            Text("isInitNFC: $isInitNFC"),
            const Text("NFC"),
            // StreamBuilder(
            //   stream: _nfcFtmPlugin.getDataStream(),
            //   builder: (context, snapshot) {
            //     if (snapshot.hasData) {
            //       return Text(snapshot.data.toString());
            //     } else {
            //       return const Text('No data');
            //     }
            //   },
            // ),
          ],
        ),
        // body: StreamBuilder(
        //   stream: _nfcFtmPlugin.getDataStream(),
        //   builder: (context, snapshot) {
        //     if (snapshot.hasData) {
        //       return Text(snapshot.data.toString());
        //     } else {
        //       return const Text('No data');
        //     }
        //   },
        // ),
      ),
    );
  }
}

class NfcDetailPage extends StatelessWidget {
  final String nfcData;
  NfcDetailPage({required this.nfcData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("NFC Details")),
      body: Center(
        child: Text("NFC Data: $nfcData"),
      ),
    );
  }
}
