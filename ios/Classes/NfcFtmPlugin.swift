import Flutter
import UIKit
import CoreNFC
import Foundation
import st25sdkFramework

// MARK: - FTM Command Constants

private let FTM_CMD_SEND_DATA: UInt8 = 5
private let FTM_CMD_READ_DATA: UInt8 = 6

// MARK: - Progress Listener

class SDKProgressListener: NSObject, ComStSt25sdkFtmprotocolFtmProtocol_TransferProgressionListener {

    private weak var plugin: NfcFtmPlugin?

    init(plugin: NfcFtmPlugin) {
        self.plugin = plugin
        super.init()
    }

    func transmissionProgress(with jint: jint, with jint2: jint, with jint3: jint) {
        plugin?.sendProgressUpdate(isTransmitted: true,
                                   tORrBytes: Int(jint),
                                   acknowledgedBytes: Int(jint2),
                                   totalSize: Int(jint3))
    }

    func receptionProgress(with jint: jint, with jint2: jint, with jint3: jint) {
        plugin?.sendProgressUpdate(isTransmitted: false,
                                   tORrBytes: Int(jint),
                                   acknowledgedBytes: Int(jint2),
                                   totalSize: Int(jint3))
    }
}

// MARK: - Pending Operation

enum PendingOperation {
    case ndefRead(FlutterResult)
    case ndefWrite(FlutterResult, String)
    case ftmSend(FlutterResult, UInt8, [UInt8])
    case tagDiscovery
}

// MARK: - NFC FTM Plugin

public class NfcFtmPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?

    private var nfcState: Int = 0
    private var isFTMmode = false

    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?

    private var rfReaderInterface: iOSRFReaderInterface?
    private var st25DVTag: ComStSt25sdkType5St25dvST25DVTag?
    private var ftmCommands: ComStSt25sdkFtmprotocolFtmCommands?
    private var nfcTag: ComStSt25sdkNFCTag?

    private var progressListener: SDKProgressListener?
    private let ftmQueue = DispatchQueue(label: "com.nfcftm.ios.ftm", qos: .userInitiated)
    private var pendingOp: PendingOperation?

    private var lastTagIdHex: String = ""
    private var lastTechList: [String] = []
    private var lastMailboxEnabled: Bool = false
    private var lastMemSize: Int = 0
    private var lastNdefLen: Int = 0

    // MARK: - FlutterPlugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "nfc_ftm_to_native",
            binaryMessenger: registrar.messenger()
        )
        let instance = NfcFtmPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.methodChannel = channel

        let eventChannel = FlutterEventChannel(
            name: "nfc_ftm_to_flutter",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - Flutter Method Call Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable": handleIsAvailable(result)
        case "state": result(nfcState)
        case "openNFC": handleOpenNFC(call, result)
        case "closeNFC": handleCloseNFC(result)
        case "openFTM": handleOpenFTM(call, result)
        case "getFTM": handleGetFTM(result)
        case "sendFTMData": handleSendFTMData(call, result)
        case "readFTMData": handleReadFTMData(call, result)
        case "FTMcancel": handleFTMcancel(result)
        case "NDEF@read": handleNDEFRead(call, result)
        case "NDEF@write": handleNDEFWrite(call, result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - isAvailable

    private func handleIsAvailable(_ result: @escaping FlutterResult) {
        let available = isNFCEnabled()
        if !available { nfcState = -1 }
        sendToastMessage(message: "isEnabledNFC: \(available)")
        result(available)
    }

    // MARK: - openNFC / closeNFC / openFTM

    private let defaultAlertMessage = "Hold smartphone near NFC tag"

    private func alertMessage(from call: FlutterMethodCall) -> String? {
        guard let args = call.arguments as? [String: Any] else { return nil }
        return args["alertMessage"] as? String
    }

    private func handleOpenNFC(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        isFTMmode = true
        cancelFTMTransfer()
        if #available(iOS 14.0, *) {
            startTagDiscoverySession(result: result, alertMessage: alertMessage(from: call))
        } else {
            nfcState = 1
            result(true)
        }
    }

    private func handleCloseNFC(_ result: @escaping FlutterResult) {
        result(disableReaderMode())
    }

    private func handleOpenFTM(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        isFTMmode = true
        cancelFTMTransfer()
        if #available(iOS 14.0, *) {
            startTagDiscoverySession(result: result, alertMessage: alertMessage(from: call))
        } else {
            nfcState = 1
            result(true)
        }
    }

    // MARK: - getFTM

    private func handleGetFTM(_ result: @escaping FlutterResult) {
        guard isFTMmode else {
            nfcState = 3
            sendTagInfoEvent()
            result(false)
            return
        }
        if nfcState == 4 {
            sendTagInfoEvent()
            result(true)
            return
        }
        if st25DVTag != nil {
            initFTM()
            sendTagInfoEvent()
            result(nfcState == 4)
            return
        }
        nfcState = 3
        sendTagInfoEvent()
        result(false)
    }

    // MARK: - sendFTMData / readFTMData

    private func handleSendFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startFTMSession(result: result, cmd: FTM_CMD_SEND_DATA, data: [UInt8](sendData.data), alertMessage: alertMessage(from: call))
    }

    private func handleReadFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rsendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startFTMSession(result: result, cmd: FTM_CMD_READ_DATA, data: [UInt8](rsendData.data), alertMessage: alertMessage(from: call))
    }

    // MARK: - FTMcancel

    private func handleFTMcancel(_ result: @escaping FlutterResult) {
        cancelFTMTransfer()
        if #available(iOS 13.0, *) {
            tagSession?.invalidate()
            tagSession = nil
        }
        result(true)
    }

    // MARK: - NDEF@read / NDEF@write

    private func handleNDEFRead(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        startNDEFReadSession(result: result, alertMessage: alertMessage(from: call))
    }

    private func handleNDEFWrite(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startNDEFWriteSession(result: result, text: data, alertMessage: alertMessage(from: call))
    }

    // MARK: - isNFCEnabled

    func isNFCEnabled() -> Bool {
        guard #available(iOS 11.0, *) else { return false }
        return NFCNDEFReaderSession.readingAvailable
    }

    // MARK: - Start NDEF Read Session

    private func startNDEFReadSession(result: @escaping FlutterResult, alertMessage: String? = nil) {
        guard ndefSession == nil else {
            sendToastMessage(message: "NFC session busy, please wait")
            result(nil)
            return
        }
        guard isNFCEnabled() else {
            sendToastMessage(message: "NFC not found")
            result(nil)
            return
        }
        pendingOp = .ndefRead(result)
        ndefSession = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: true
        )
        ndefSession?.alertMessage = alertMessage ?? defaultAlertMessage
        ndefSession?.begin()
    }

    // MARK: - Start NDEF Write Session

    @available(iOS 13.0, *)
    private func startNDEFWriteSessionViaTagReader(result: @escaping FlutterResult, text: String, alertMessage: String? = nil) {
        guard tagSession == nil else {
            sendToastMessage(message: "NFC session busy, please wait")
            result(false)
            return
        }
        guard isNFCEnabled() else {
            sendToastMessage(message: "NFC not found")
            result(false)
            return
        }
        pendingOp = .ndefWrite(result, text)
        tagSession = NFCTagReaderSession(
            pollingOption: .iso15693,
            delegate: self,
            queue: nil
        )
        tagSession?.alertMessage = alertMessage ?? defaultAlertMessage
        tagSession?.begin()
    }

    private func startNDEFWriteSession(result: @escaping FlutterResult, text: String, alertMessage: String? = nil) {
        if #available(iOS 13.0, *) {
            startNDEFWriteSessionViaTagReader(result: result, text: text, alertMessage: alertMessage)
        } else {
            sendToastMessage(message: "NDEF write requires iOS 13.0+")
            result(false)
        }
    }

    // MARK: - Start Tag Discovery Session

    @available(iOS 14.0, *)
    private func startTagDiscoverySession(result: @escaping FlutterResult, alertMessage: String? = nil) {
        guard tagSession == nil else {
            sendToastMessage(message: "NFC session busy, please wait")
            result(false)
            return
        }
        guard isNFCEnabled() else {
            sendToastMessage(message: "NFC not found")
            result(false)
            return
        }
        pendingOp = .tagDiscovery
        tagSession = NFCTagReaderSession(
            pollingOption: [.iso15693],
            delegate: self,
            queue: nil
        )
        tagSession?.alertMessage = alertMessage ?? defaultAlertMessage
        tagSession?.begin()
        nfcState = 1
        result(true)
    }

    // MARK: - Start FTM Session

    @available(iOS 14.0, *)
    private func startFTMSessionViaTagReader(result: @escaping FlutterResult, cmd: UInt8, data: [UInt8], alertMessage: String? = nil) {
        guard tagSession == nil else {
            sendToastMessage(message: "NFC session busy, please wait")
            result([])
            return
        }
        guard isNFCEnabled() else {
            sendToastMessage(message: "NFC not found")
            result([])
            return
        }
        pendingOp = .ftmSend(result, cmd, data)
        tagSession = NFCTagReaderSession(
            pollingOption: [.iso15693],
            delegate: self,
            queue: nil
        )
        tagSession?.alertMessage = alertMessage ?? defaultAlertMessage
        tagSession?.begin()
    }

    private func startFTMSession(result: @escaping FlutterResult, cmd: UInt8, data: [UInt8], alertMessage: String? = nil) {
        if #available(iOS 14.0, *) {
            startFTMSessionViaTagReader(result: result, cmd: cmd, data: data, alertMessage: alertMessage)
        } else {
            sendToastMessage(message: "FTM requires iOS 14.0+")
            result([])
        }
    }

    // MARK: - disableReaderMode

    func disableReaderMode() -> Bool {
        cancelFTMTransfer()
        nfcState = 0
        pendingOp = nil
        ndefSession?.invalidate()
        ndefSession = nil
        if #available(iOS 13.0, *) {
            tagSession?.invalidate()
            tagSession = nil
        }
        return true
    }

    // MARK: - SDK Tag Init (unified, matches Android pattern)

    @available(iOS 14.0, *)
    private func initSDKTag(
        isoTag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        tagIdHex: String,
        techList: [String],
        completion: @escaping (Bool) -> Void
    ) {
         DispatchQueue.global(qos: .userInitiated).async { [weak self] in
             guard let self = self else { return }

             self.lastTagIdHex = tagIdHex
             self.lastTechList = techList

             let rf = iOSRFReaderInterface(isoTag: isoTag, session: session)
            let uidArray = IOSByteArray(nsData: Data(isoTag.identifier))

             var isDVTag = false
             var isMailboxEnabled = false
             var memSize: Int = 0
             var ndefLen: Int = 0
             var ndefLang: String = ""
             var ndefText: String = ""
             var ndefPayload: FlutterStandardTypedData = FlutterStandardTypedData(bytes: Data())

             SwiftTryCatch.try({
                 let sdkTag = ComStSt25sdkType5St25dvST25DVTag(
                     comStSt25sdkRFReaderInterface: rf,
                     with: uidArray
                 )
                 self.rfReaderInterface = rf
                 self.st25DVTag = sdkTag
                 self.nfcTag = sdkTag
                 self.nfcState = 3
                 isDVTag = true

                 memSize = Int(sdkTag.getMemSizeInBytes())
                 if let ndefMsg = sdkTag.readNdefMessage() {
                     ndefLen = Int(ndefMsg.getLength())
                     if let serialized = ndefMsg.serialize()?.toNSData(),
                        let nfcMsg = try? NFCNDEFMessage(data: serialized) {
                         if let parsed = iOSNdef.parseTextFromNDEF(nfcMsg) {
                             ndefLang = parsed.lang
                             ndefText = parsed.text
                             ndefPayload = FlutterStandardTypedData(bytes: parsed.payload)
                         }
                     }
                 }
             }, catch: { ex in
                 let msg = ex.description
                 if !msg.contains("CMD_FAILED") {
                     print("[FTM] initSDKTag exception: \(msg)")
                 }
             }, finallyBlock: {})

             if isDVTag, let tag = self.st25DVTag {
                 SwiftTryCatch.try({
                  isMailboxEnabled = tag.isMailboxEnabled(withBoolean: true)
              }, catch: { _ in
              }, finallyBlock: {})
              }
              self.lastMailboxEnabled = isMailboxEnabled
              self.lastMemSize = memSize
              self.lastNdefLen = ndefLen

             if !isDVTag {
                 self.st25DVTag = nil
                 self.nfcTag = nil
                 self.nfcState = 2
             }

             if self.isFTMmode && self.st25DVTag != nil && isMailboxEnabled {
                 self.initFTM()
             }

             var ndefData: [String: Any] = [:]
            if ndefLen > 0 {
                ndefData["lang"] = ndefLang
                ndefData["data"] = ndefText
                ndefData["payload"] = ndefPayload
            }

             var returnVal: [String: Any] = [:]
             returnVal["k"] = "onDiscovered"
             returnVal["id"] = tagIdHex
             returnVal["type"] = "[\(techList.joined(separator: ", "))]"
             returnVal["memSize"] = memSize
             returnVal["ndefLength"] = ndefLen
             returnVal["ndef"] = ndefData
             returnVal["isFTMmode"] = isFTMmode && isDVTag && isMailboxEnabled

             DispatchQueue.main.async { [weak self] in
                self?.eventSink?(returnVal)
            }
            session.invalidate()
            completion(isDVTag)
        }
    }

    // MARK: - SDK Init + FTM Operation

    @available(iOS 14.0, *)
    private func initSDKTagThenFTM(
        isoTag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        cmd: UInt8,
        data: [UInt8],
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var exception: NSException?
            let rf = iOSRFReaderInterface(isoTag: isoTag, session: session)

            SwiftTryCatch.try({
                let uidArray = IOSByteArray(nsData: Data(isoTag.identifier))
                let sdkTag = ComStSt25sdkType5St25dvST25DVTag(
                    comStSt25sdkRFReaderInterface: rf,
                    with: uidArray
                )
                 self.rfReaderInterface = rf
                 self.st25DVTag = sdkTag

                 self.lastMemSize = Int(sdkTag.getMemSizeInBytes())
                 self.lastNdefLen = 0
                 if let ndefMsg = sdkTag.readNdefMessage() {
                     self.lastNdefLen = Int(ndefMsg.getLength())
                 }

                 let cmds = ComStSt25sdkFtmprotocolFtmCommands(comStSt25sdkType5St25dvST25DVTag: sdkTag)
                 self.ftmCommands = cmds
                 self.progressListener = SDKProgressListener(plugin: self)
                 self.nfcState = 4
             }, catch: { ex in
                 exception = ex
             }, finallyBlock: {})

             if let ex = exception {
                 self.sendToastMessage(message: "ST25DVTag init error: \(ex.description)")
                 session.invalidate()
                 DispatchQueue.main.async { result([]) }
                 return
             }

             // isMailboxEnabled read in separate try-catch to avoid failing
             // the entire init when mailbox check throws during FTM session
             if let tag = self.st25DVTag {
                 SwiftTryCatch.try({
                     self.lastMailboxEnabled = tag.isMailboxEnabled(withBoolean: true)
                 }, catch: { _ in }, finallyBlock: {})
             }

            if self.ftmCommands != nil {
                self.performFTMOperation(cmd: cmd, data: data, isoTag: isoTag, session: session, result: result)
            } else {
                session.invalidate()
                DispatchQueue.main.async { result([]) }
            }
        }
    }

    // MARK: - ST25DV Product Check

    private func isST25DVProduct(_ productID: ComStSt25sdkTagHelper_ProductID?) -> Bool {
        guard let pid = productID else { return false }
        switch pid {
        case .PRODUCT_ST_ST25DV04K_I, .PRODUCT_ST_ST25DV04K_J,
             .PRODUCT_ST_ST25DV16K_I, .PRODUCT_ST_ST25DV16K_J,
             .PRODUCT_ST_ST25DV64K_I, .PRODUCT_ST_ST25DV64K_J,
             .PRODUCT_ST_ST25DV04KC_I, .PRODUCT_ST_ST25DV04KC_J,
             .PRODUCT_ST_ST25DV16KC_I, .PRODUCT_ST_ST25DV16KC_J,
             .PRODUCT_ST_ST25DV64KC_I, .PRODUCT_ST_ST25DV64KC_J,
             .PRODUCT_ST_ST25DV02K_W1, .PRODUCT_ST_ST25DV02K_W2:
            return true
        default:
            return false
        }
    }

    // MARK: - initFTM

    func initFTM() {
        guard let tag = st25DVTag else {
            nfcState = 3
            sendToastMessage(message: "initFTM: st25DVTag is nil")
            return
        }

        var commands: ComStSt25sdkFtmprotocolFtmCommands?
        var exception: NSException?

        SwiftTryCatch.try({
            commands = ComStSt25sdkFtmprotocolFtmCommands(comStSt25sdkType5St25dvST25DVTag: tag)
        }, catch: { ex in
            exception = ex
        }, finallyBlock: {})
        if let ex = exception {
            sendToastMessage(message: "initFTM error: \(ex.description)")
            nfcState = 3

            return
        }

        guard let cmds = commands else {
            nfcState = 3
            sendToastMessage(message: "initFTM: failed to create FtmCommands")
            return
        }

        ftmCommands = cmds
        progressListener = SDKProgressListener(plugin: self)
        nfcState = 4
    }

    // MARK: - cancelFTMTransfer

    func cancelFTMTransfer() {
        if let cmds = ftmCommands {
            SwiftTryCatch.try({
                cmds.cancelCurrentTransfer()
            }, catch: { _ in }, finallyBlock: {})
        }
        ftmCommands = nil
        st25DVTag = nil
        rfReaderInterface = nil
    }

    // MARK: - FTM Operations

    @available(iOS 14.0, *)
    private func performFTMOperation(
        cmd: UInt8,
        data: [UInt8],
        isoTag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        result: @escaping FlutterResult
    ) {
        guard let cmds = ftmCommands else {
            sendToastMessage(message: "FTM not initialized")
            session.invalidate()
            result([])
            return
        }

        let listener = progressListener ?? SDKProgressListener(plugin: self)

        ftmQueue.async { [weak self] in
            var responseData: IOSByteArray?
            var exception: NSException?

            SwiftTryCatch.try({
                let dataArray = IOSByteArray(nsData: Data(data))
                responseData = cmds.sendCmdAndWaitForCompletion(
                    withByte: jbyte(cmd),
                    with: dataArray,
                    withBoolean: true,
                    withBoolean: true,
                    with: listener,
                    with: 10000
                )
            }, catch: { ex in
                exception = ex
            }, finallyBlock: {})

            DispatchQueue.main.async {
                session.invalidate()
                if let ex = exception {
                    self?.sendToastMessage(message: "FTM error: \(ex.description)")
                    self?.sendTagInfoEvent()
                    result([])
                    return
                }

                guard let resp = responseData else {
                    self?.sendToastMessage(message: "FTM error: no response")
                    self?.sendTagInfoEvent()
                    result([])
                    return
                }

                let response = resp.toNSData() ?? Data()
                self?.sendProgressUpdate(isTransmitted: false,
                                         tORrBytes: response.count,
                                         acknowledgedBytes: response.count,
                                         totalSize: response.count)
                self?.sendTagInfoEvent()
                result([UInt8](response))
            }
        }
    }

    // MARK: - Progress Update

    public func sendProgressUpdate(isTransmitted: Bool, tORrBytes: Int, acknowledgedBytes: Int, totalSize: Int) {
        guard totalSize > 0, let sink = eventSink else { return }
        let progress = totalSize > 0 ? (acknowledgedBytes * 100) / totalSize : 0
        let secondaryProgress = totalSize > 0 ? (tORrBytes * 100) / totalSize : 0
        var dataMap: [String: Any] = [:]
        dataMap["progress"] = progress
        dataMap["secondaryProgress"] = secondaryProgress
        dataMap["acknowledgedBytes"] = acknowledgedBytes
        dataMap["totalSize"] = totalSize
        if isTransmitted {
            dataMap["k"] = "transmissionProgress"
            dataMap["transmittedBytes"] = tORrBytes
        } else {
            dataMap["k"] = "receptionProgress"
            dataMap["receivedBytes"] = tORrBytes
        }
        DispatchQueue.main.async { sink(dataMap) }
    }

    // MARK: - NDEF Write via NFCNDEFTag

    @available(iOS 13.0, *)
    private func writeNDEFViaNDEFTag(
        to isoTag: NFCISO15693Tag,
        text: String,
        session: NFCTagReaderSession,
        result: @escaping FlutterResult
    ) {
        guard let ndefTag = isoTag as? NFCNDEFTag else {
            sendToastMessage(message: "Tag does not support NFCNDEFTag")
            session.invalidate()
            result(false)
            return
        }
        guard ndefTag.isAvailable else {
            sendToastMessage(message: "NDEF tag not available")
            session.invalidate()
            result(false)
            return
        }
        guard let ndefMessage = buildTextNDEFMessage(text: text) else {
            sendToastMessage(message: "Failed to build NDEF message")
            session.invalidate()
            result(false)
            return
        }
        ndefTag.writeNDEF(ndefMessage) { writeError in
            if let nfcError = writeError as? NFCReaderError,
               nfcError.code == .ndefReaderSessionErrorZeroLengthMessage {
                self.sendToastMessage(message: "write NDEF success")
                self.sendTagInfoEvent()
                session.invalidate()
                result(true)
                return
            }
            if let writeError = writeError {
                self.sendToastMessage(message: "write NDEF error: \(writeError.localizedDescription)")
                self.sendTagInfoEvent()
                session.invalidate()
                result(false)
                return
            }
            self.sendToastMessage(message: "write NDEF success")
            self.sendTagInfoEvent()
            session.invalidate()
            result(true)
        }
    }

    private func buildTextNDEFMessage(text: String, lang: String = "en") -> NFCNDEFMessage? {
        let locale = JavaUtilLocale(nsString: lang)
        let sdkRecord = ComStSt25sdkNdefTextRecord(
            nsString: text,
            with: locale,
            withBoolean: true
        )
        let sdkMsg = ComStSt25sdkNdefNDEFMsg()
        sdkMsg.addRecord(with: sdkRecord)
        guard let serialized = sdkMsg.serialize()?.toNSData() else { return nil }
        return try? NFCNDEFMessage(data: serialized)
    }

    // MARK: - Toast Message

    func sendToastMessage(message: String) {
        var messageMap: [String: String] = [:]
        messageMap["k"] = "toast"
        messageMap["v"] = message
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(messageMap)
        }
    }

    // MARK: - Utilities

    private func bytesToHex(_ bytes: [UInt8]) -> String {
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - FlutterStreamHandler

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        progressListener = SDKProgressListener(plugin: self)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        progressListener = nil
        disableReaderMode()
        return nil
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NfcFtmPlugin: NFCNDEFReaderSessionDelegate {

    public func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        nfcState = 2

        guard let op = pendingOp else {
             var returnVal: [String: Any] = [:]
             returnVal["k"] = "onDiscovered"
            returnVal["id"] = ""
            returnVal["type"] = "[]"
            returnVal["memSize"] = 0
            returnVal["ndefLength"] = messages.first?.length ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(returnVal)
            }
            return
        }

        switch op {
        case .ndefRead(let result):
            var ndefData: [String: Any] = [:]
            for message in messages {
                for record in message.records {
                    let payload = record.payload
                    guard payload.count > 1 else { continue }
                    let langLen = Int(payload[0] & 0x3F)
                    let isUtf16 = (payload[0] & 0x80) != 0
                    guard payload.count > 1 + langLen else { continue }
                    let langBytes = payload.subdata(in: 1..<(1 + langLen))
                    let valueBytes = payload.subdata(in: (1 + langLen)..<payload.count)
                    ndefData["lang"] = String(data: langBytes, encoding: .ascii) ?? ""
                    if isUtf16 {
                        ndefData["data"] = String(data: valueBytes, encoding: .utf16) ?? ""
                    } else {
                        ndefData["data"] = String(data: valueBytes, encoding: .utf8) ?? ""
                    }
                    ndefData["payload"] = FlutterStandardTypedData(bytes: payload)
                }
            }
            pendingOp = nil
            sendTagInfoEvent()
            result(ndefData)
        default:
            pendingOp = nil
        }
    }

    public func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                if pendingOp != nil {
                    sendToastMessage(message: "NFC read cancelled.")
                }
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                break
            default:
                sendToastMessage(message: "NFC error: \(error.localizedDescription)")
            }
        }
        if let op = pendingOp {
            pendingOp = nil
            switch op {
            case .ndefRead(let result):
                result([:])
            default:
                break
            }
        }
        ndefSession = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate

@available(iOS 14.0, *)
extension NfcFtmPlugin: NFCTagReaderSessionDelegate {

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    public func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                if pendingOp != nil {
                    sendToastMessage(message: "NFC read cancelled.")
                }
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                break
            default:
                sendToastMessage(message: "NFC error: \(error.localizedDescription)")
            }
        }
        if let op = pendingOp {
            pendingOp = nil
            switch op {
            case .ndefWrite(let result, _):
                result(false)
            case .ftmSend(let result, _, _):
                result([])
            default:
                break
            }
        }
        tagSession = nil
    }

    public func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {
        guard let tag = tags.first else { return }
        nfcState = 2

        var tagIdHex = ""
        var techList: [String] = []
        var isoTag: NFCISO15693Tag?

        switch tag {
        case .iso15693(let tag):
            isoTag = tag
            tagIdHex = bytesToHex(tag.identifier.map { $0 })
            techList.append("android.nfc.tech.NfcV")
        case .iso7816(let tag):
            tagIdHex = bytesToHex([UInt8](tag.identifier))
            techList.append("android.nfc.tech.IsoDep")
        case .miFare(let mifareTag):
            tagIdHex = bytesToHex([UInt8](mifareTag.identifier))
            techList.append("android.nfc.tech.NfcA")
        default:
            break
        }

        lastTagIdHex = tagIdHex
        lastTechList = techList

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.sendToastMessage(message: "Tag connect error: \(error.localizedDescription)")
                self.finishPendingOp(withError: error.localizedDescription)
                session.invalidate()
                return
            }

            if let op = self.pendingOp {
                self.pendingOp = nil
                switch op {
                case .ndefWrite(let result, let text):
                    if let iso = isoTag {
                        self.writeNDEFViaNDEFTag(to: iso, text: text, session: session, result: result)
                    } else {
                        self.sendToastMessage(message: "Tag does not support NDEF write")
                        session.invalidate()
                        result(false)
                    }
                    return
                case .ftmSend(let result, let cmd, let data):
                    if let iso = isoTag {
                        self.initSDKTagThenFTM(isoTag: iso, session: session, cmd: cmd, data: data, result: result)
                    } else {
                        session.invalidate()
                        result([])
                    }
                    return
                case .tagDiscovery:
                    break
                default:
                    session.invalidate()
                    return
                }
            }

            if self.isFTMmode, let iso = isoTag {
                self.lastTagIdHex = tagIdHex
                self.lastTechList = techList
                self.initSDKTag(isoTag: iso, session: session, tagIdHex: tagIdHex, techList: techList) { _ in }
                return
            }

            self.lastTagIdHex = tagIdHex
            self.lastTechList = techList

             var returnVal: [String: Any] = [:]
             returnVal["k"] = "onDiscovered"
             returnVal["id"] = tagIdHex
             returnVal["type"] = "[\(techList.joined(separator: ", "))]"
             returnVal["memSize"] = 0
             returnVal["ndefLength"] = 0
             returnVal["isFTMmode"] = false
             DispatchQueue.main.async { [weak self] in
                self?.eventSink?(returnVal)
            }
            session.invalidate()
        }
    }

    // MARK: - sendTagInfoEvent

    private func sendTagInfoEvent() {
        guard let sink = eventSink else { return }

        var returnVal: [String: Any] = [:]
        returnVal["k"] = "onDiscovered"
        returnVal["id"] = lastTagIdHex
        returnVal["type"] = "[\(lastTechList.joined(separator: ", "))]"
        returnVal["memSize"] = lastMemSize
        returnVal["ndefLength"] = lastNdefLen
        returnVal["isFTMmode"] = isFTMmode && st25DVTag != nil && lastMailboxEnabled

        DispatchQueue.main.async {
            sink(returnVal)
        }
    }

    private func finishPendingOp(withError msg: String) {
        guard let op = pendingOp else { return }
        pendingOp = nil
        switch op {
        case .ndefRead(let result):
            result([:])
        case .ndefWrite(let result, _):
            result(false)
        case .ftmSend(let result, _, _):
            result([])
        case .tagDiscovery:
            break
        }
    }
}
