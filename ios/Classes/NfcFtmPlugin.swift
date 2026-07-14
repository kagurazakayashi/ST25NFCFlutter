import Flutter
import UIKit
import CoreNFC
import Foundation
import st25sdkFramework

// MARK: - FTM Command Constants (matching ST25SDK FtmCommands.h)

private let FTM_CMD_SEND_DATA: UInt8 = 5
private let FTM_CMD_READ_DATA: UInt8 = 6

// Header size constants (from Iso15693Protocol.h)
private let ISO15693_HEADER_SIZE_UID: Int = 10
private let ISO15693_CUSTOM_ST_HEADER_SIZE_UID: Int = 11

// MARK: - Progress Listener (bridges SDK -> Flutter EventChannel)

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

    // MARK: - Flutter channel properties

    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?

    // MARK: - NFC State

    private var nfcState: Int = 0

    private var isFTMmode = false

    // MARK: - NFC Sessions

    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?

    // MARK: - ST25SDK objects

    private var rfReaderInterface: iOSRFReaderInterface?
    private var st25DVTag: ComStSt25sdkType5St25dvST25DVTag?
    private var ftmCommands: ComStSt25sdkFtmprotocolFtmCommands?
    private var mST25DVTag: AnyObject?

    // MARK: - Progress listener

    private var progressListener: SDKProgressListener?

    // MARK: - FTM background queue

    private let ftmQueue = DispatchQueue(label: "com.nfcftm.ios.ftm", qos: .userInitiated)

    // MARK: - Pending operation

    private var pendingOp: PendingOperation?

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
        case "isAvailable":
            handleIsAvailable(result)
        case "state":
            result(nfcState)
        case "openNFC":
            handleOpenNFC(result)
        case "closeNFC":
            handleCloseNFC(result)
        case "openFTM":
            handleOpenFTM(result)
        case "getFTM":
            handleGetFTM(result)
        case "sendFTMData":
            handleSendFTMData(call, result)
        case "readFTMData":
            handleReadFTMData(call, result)
        case "FTMcancel":
            handleFTMcancel(result)
        case "NDEF@read":
            handleNDEFRead(result)
        case "NDEF@write":
            handleNDEFWrite(call, result)
        default:
            result(FlutterMethodNotImplemented)
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

    private func handleOpenNFC(_ result: @escaping FlutterResult) {
        isFTMmode = false
        cancelFTMTransfer()
        nfcState = 1
        result(true)
    }

    private func handleCloseNFC(_ result: @escaping FlutterResult) {
        result(disableReaderMode())
    }

    private func handleOpenFTM(_ result: @escaping FlutterResult) {
        isFTMmode = true
        cancelFTMTransfer()
        nfcState = 1
        result(true)
    }

    // MARK: - getFTM

    private func handleGetFTM(_ result: @escaping FlutterResult) {
        guard isFTMmode else {
            nfcState = 3
            result(false)
            return
        }
        nfcState = 3
        result(true)
    }

    // MARK: - sendFTMData / readFTMData

    private func handleSendFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startFTMSession(result: result, cmd: FTM_CMD_SEND_DATA, data: [UInt8](sendData.data))
    }

    private func handleReadFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rsendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startFTMSession(result: result, cmd: FTM_CMD_READ_DATA, data: [UInt8](rsendData.data))
    }

    // MARK: - FTMcancel

    private func handleFTMcancel(_ result: @escaping FlutterResult) {
        cancelFTMTransfer()
    }

    // MARK: - NDEF@read / NDEF@write

    private func handleNDEFRead(_ result: @escaping FlutterResult) {
        startNDEFReadSession(result: result)
    }

    private func handleNDEFWrite(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        startNDEFWriteSession(result: result, text: data)
    }

    // MARK: - isNFCEnabled

    func isNFCEnabled() -> Bool {
        if #available(iOS 11.0, *) {
            return NFCNDEFReaderSession.readingAvailable
        }
        return false
    }

    // MARK: - Start NDEF Read Session

    private func startNDEFReadSession(result: @escaping FlutterResult) {
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
        ndefSession?.alertMessage = "将 NFC 标签靠近设备以读取。"
        ndefSession?.begin()
    }

    // MARK: - Start NDEF Write Session

    @available(iOS 13.0, *)
    private func startNDEFWriteSessionViaTagReader(result: @escaping FlutterResult, text: String) {
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
        tagSession?.alertMessage = "将 NFC 标签靠近设备以写入。"
        tagSession?.begin()
    }

    private func startNDEFWriteSession(result: @escaping FlutterResult, text: String) {
        if #available(iOS 13.0, *) {
            startNDEFWriteSessionViaTagReader(result: result, text: text)
        } else {
            sendToastMessage(message: "NDEF write requires iOS 13.0+")
            result(false)
        }
    }

    // MARK: - Start FTM Session

    @available(iOS 14.0, *)
    private func startFTMSessionViaTagReader(result: @escaping FlutterResult, cmd: UInt8, data: [UInt8]) {
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
        tagSession?.alertMessage = "将 NFC 标签靠近设备以传输。"
        tagSession?.begin()
    }

    private func startFTMSession(result: @escaping FlutterResult, cmd: UInt8, data: [UInt8]) {
        if #available(iOS 14.0, *) {
            startFTMSessionViaTagReader(result: result, cmd: cmd, data: data)
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

    // MARK: - Lazy SDK init + FTM

    @available(iOS 14.0, *)
    private func initSDKTagThenFTM(
        isoTag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        cmd: UInt8,
        data: [UInt8],
        result: @escaping FlutterResult
    ) {
        // Run SDK init on background queue to avoid deadlocking the NFC delegate queue
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

            self.performFTMOperation(cmd: cmd, data: data, isoTag: isoTag, session: session, result: result)
        }
    }

    // MARK: - initFTM (SDK-based)

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

    // MARK: - cancelFTMTransfer (SDK-based)

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

    // MARK: - FTM Operations (SDK-based, using sendCmdAndWaitForCompletion)

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

            session.invalidate()

            DispatchQueue.main.async {
                if let ex = exception {
                    self?.sendToastMessage(message: "FTM error: \(ex.description)")
                    result([])
                    return
                }

                guard let resp = responseData else {
                    self?.sendToastMessage(message: "FTM error: no response")
                    result([])
                    return
                }

                let response = resp.toNSData() ?? Data()
                self?.sendProgressUpdate(isTransmitted: false,
                                         tORrBytes: response.count,
                                         acknowledgedBytes: response.count,
                                         totalSize: response.count)
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
        let textPayload = buildUTF8TextNDEFPayload(text: text)
        let payload = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: Data([0x54]),
            identifier: Data(),
            payload: textPayload
        )
        let message = NFCNDEFMessage(records: [payload])
        ndefTag.writeNDEF(message) { writeError in
            if let nfcError = writeError as? NFCReaderError,
               nfcError.code == .ndefReaderSessionErrorZeroLengthMessage {
                self.sendToastMessage(message: "写入成功")
                session.invalidate()
                result(true)
                return
            }
            if let writeError = writeError {
                self.sendToastMessage(message: "write NDEF error: \(writeError.localizedDescription)")
                session.invalidate()
                result(false)
                return
            }
            self.sendToastMessage(message: "写入成功")
            session.invalidate()
            result(true)
        }
    }

    private func buildUTF8TextNDEFPayload(text: String, lang: String = "en") -> Data {
        let statusByte: UInt8 = UInt8(lang.count)
        guard let langData = lang.data(using: .ascii),
              let textData = text.data(using: .utf8)
        else { return Data() }
        var payload = Data()
        payload.append(statusByte)
        payload.append(langData)
        payload.append(textData)
        return payload
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
                    sendToastMessage(message: "用户取消了 NFC 读取。")
                }
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                break
            default:
                sendToastMessage(message: "NFC 错误：\(error.localizedDescription)")
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
                    sendToastMessage(message: "用户取消了 NFC 读取。")
                }
            case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                break
            default:
                sendToastMessage(message: "NFC 错误：\(error.localizedDescription)")
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

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                self.sendToastMessage(message: "Tag connect error: \(error.localizedDescription)")
                self.finishPendingOp(withError: error.localizedDescription)
                session.invalidate()
                return
            }

            self.mST25DVTag = tag as AnyObject

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
                case .ftmSend(let result, let cmd, let data):
                    if let iso = isoTag {
                        self.initSDKTagThenFTM(isoTag: iso, session: session, cmd: cmd, data: data, result: result)
                    } else {
                        session.invalidate()
                        result([])
                    }
                default:
                    session.invalidate()
                }
                return
            }

            var returnVal: [String: Any] = [:]
            returnVal["k"] = "onDiscovered"
            returnVal["id"] = tagIdHex
            returnVal["type"] = "[\(techList.joined(separator: ", "))]"
            returnVal["memSize"] = 0
            returnVal["ndefLength"] = 0
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(returnVal)
            }
            session.invalidate()
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
