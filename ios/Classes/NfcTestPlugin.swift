import Flutter
import UIKit
import CoreNFC

public class NfcFtmPlugin: NSObject, FlutterPlugin,FlutterStreamHandler,NFCNDEFReaderSessionDelegate  {
    
    private var eventSink: FlutterEventSink? // 保存事件流回调对象
    // NFC 状态
    // -1: 未找到 NFC
    // 0: 未开启 NFC
    // 1: NFC 已开启
    // 2: 读取到 NFC 标签
    // 3: NFC 已开启，FTM 模式，未初始化 mFtmCommands
    // 4: NFC 已开启，FTM 模式
    private var nfcState:Int = 0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "nfc_ftm_to_native", binaryMessenger: registrar.messenger())
        let instance = NfcFtmPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // 注册 EventChannel
        let eventChannel = FlutterEventChannel(name: "nfc_ftm_to_flutter", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("### call.method: \(call.method)")
        switch call.method {
        case "isAvailable":
            let isAvailable = isNFCEnabled()
            if !isAvailable{
                nfcState = -1
            }
            result(isAvailable)
            break
            
        case "state":
            result(nfcState)
            break
        case "openNFC":
            let isDone = openNFC()
            print("### openNFC: \(isDone)")
            result(isDone)
            break
        case "closeNFC":
            result(true)
            break
        case "openFTM":
            break
        case "getFTM":
            break
        case "sendFTMData":
            break
        case "readFTMData":
            break
        case "FTMcancel":
            break
        case "NDEF@read":
            break
        case "NDEF@write":
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - 检查设备是否支持 NFC 功能
    func isNFCEnabled() -> Bool {
        if #available(iOS 11.0, *) {
            print("$$$ 123 \(NFCNDEFReaderSession.readingAvailable)")
            return NFCNDEFReaderSession.readingAvailable
        } else {
            // iOS 11 以下不支持 NFC
            print("$$$ iOS 11 以下不支持 NFC")
            return false
        }
    }
    
    // MARK: - 开启NFC
    func openNFC() -> Bool {
        if #unavailable(iOS 11.0) {
            sendToastMessage(message:"Requires iOS 11.0 or above");
            return false
        }
        let isAvailable = isNFCEnabled()
        if !isAvailable {
            sendToastMessage(message: "NFC not found")
            return false
        }
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = "将 NFC 标签靠近设备以扫描。"
        session.begin()
        return true
    }
    
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
    /// 读取到 NFC 标签时回调
    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        for message in messages {
            for record in message.records {
                if let payload = String(data: record.payload, encoding: .utf8) {
                    print("NFC 数据：\(payload)")
                }
            }
        }
    }
    
    /// 错误处理
    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                print("用户取消了 NFC 读取。")
            default:
                print("NFC 错误：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 向 Flutter 发送 toast 信息
    func sendToastMessage(message: String) {
        var messageMap = [String: String]()
        messageMap["k"]="toast"
        messageMap["v"]=message
        eventSink?(messageMap)
    }
    
    // 实现 FlutterStreamHandler 协议
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // 可以在连接后立即发送初始事件
        self.eventSink?(["status": "connected"])
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil // 取消监听时清理事件回调对象
        return nil
    }
    
    // 发送事件到 Flutter
    private func sendEvent(data: Any) {
        guard let eventSink = eventSink else {
            print("EventSink is not available")
            return
        }
        eventSink(data)
    }
}
