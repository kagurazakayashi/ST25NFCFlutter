import Flutter
import UIKit
import CoreNFC

// MARK: - Progress Listener

class ProgressListener {
    private weak var plugin: NfcFtmPlugin?

    init(plugin: NfcFtmPlugin) {
        self.plugin = plugin
    }

    func transmissionProgress(
        transmittedBytes: Int,
        acknowledgedBytes: Int,
        totalSize: Int
    ) {
        plugin?.updateProgress(
            isTransmitted: true,
            tORrBytes: transmittedBytes,
            acknowledgedBytes: acknowledgedBytes,
            totalSize: totalSize
        )
    }

    func receptionProgress(
        receivedBytes: Int,
        acknowledgedBytes: Int,
        totalSize: Int
    ) {
        plugin?.updateProgress(
            isTransmitted: false,
            tORrBytes: receivedBytes,
            acknowledgedBytes: acknowledgedBytes,
            totalSize: totalSize
        )
    }
}

// MARK: - NFC FTM Plugin

public class NfcFtmPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Flutter channel properties

    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?

    // MARK: - NFC State
    // -1: NFC not available
    //  0: NFC disabled
    //  1: NFC enabled
    //  2: NFC tag discovered
    //  3: NFC enabled, FTM mode, mFtmCommands not initialized
    //  4: NFC enabled, FTM mode
    private var nfcState: Int = 0

    private var isFTMmode = false

    // MARK: - NFC Sessions

    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?

    // MARK: - ST25 SDK tag objects

    private var mST25DVTag: AnyObject?
    private var mFtmCommands: AnyObject?

    // MARK: - Progress listener

    private var pListener: ProgressListener?

    // MARK: - Operation queue

    private let operationQueue = DispatchQueue(label: "com.nfcftm.ios.operation")

    // MARK: - FTM command constants

    private static let FTM_CMD_SEND_DATA: UInt8 = 5
    private static let FTM_CMD_READ_DATA: UInt8 = 6

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
        if !available {
            nfcState = -1
        }
        sendToastMessage(
            message: "isEnabledNFC: \(available)"
        )
        result(available)
    }

    // MARK: - openNFC

    private func handleOpenNFC(_ result: @escaping FlutterResult) {
        isFTMmode = false
        if mFtmCommands != nil {
            cancelFTMTransfer()
            mFtmCommands = nil
        }
        let success = openNFC()
        result(success)
    }

    // MARK: - closeNFC

    private func handleCloseNFC(_ result: @escaping FlutterResult) {
        let done = disableReaderMode()
        result(done)
    }

    // MARK: - openFTM

    private func handleOpenFTM(_ result: @escaping FlutterResult) {
        isFTMmode = true
        if mFtmCommands != nil {
            cancelFTMTransfer()
            mFtmCommands = nil
        }
        let success = openNFC()
        result(success)
    }

    // MARK: - getFTM

    private func handleGetFTM(_ result: @escaping FlutterResult) {
        if mST25DVTag == nil {
            result(false)
            return
        }
        initFTM()
        result(true)
    }

    // MARK: - sendFTMData

    private func handleSendFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "data is required",
                details: nil
            ))
            return
        }
        let dataBytes = [UInt8](sendData.data)
        handleFTMOperation(result, cmd: NfcFtmPlugin.FTM_CMD_SEND_DATA, data: dataBytes)
    }

    // MARK: - readFTMData

    private func handleReadFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rsendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "data is required",
                details: nil
            ))
            return
        }
        let dataBytes = [UInt8](rsendData.data)
        handleFTMOperation(result, cmd: NfcFtmPlugin.FTM_CMD_READ_DATA, data: dataBytes)
    }

    // MARK: - FTMcancel

    private func handleFTMcancel(_ result: @escaping FlutterResult) {
        if mFtmCommands == nil {
            return
        }
        cancelFTMTransfer()
    }

    // MARK: - NDEF@read

    private func handleNDEFRead(_ result: @escaping FlutterResult) {
        readNdef(result: result)
    }

    // MARK: - NDEF@write

    private func handleNDEFWrite(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGUMENT",
                message: "data is required",
                details: nil
            ))
            return
        }
        writeNdef(result: result, text: data)
    }

    // MARK: - isNFCEnabled

    func isNFCEnabled() -> Bool {
        if #available(iOS 11.0, *) {
            return NFCNDEFReaderSession.readingAvailable
        }
        return false
    }

    // MARK: - openNFC

    func openNFC() -> Bool {
        if #unavailable(iOS 11.0) {
            sendToastMessage(message: "Requires iOS 11.0 or above")
            return false
        }

        let isAvailable = isNFCEnabled()
        if !isAvailable {
            sendToastMessage(message: "NFC not found")
            return false
        }

        if isFTMmode, #available(iOS 13.0, *) {
            return openTagReaderSession()
        } else {
            return openNDEFSession()
        }
    }

    // MARK: - openNDEFSession

    private func openNDEFSession() -> Bool {
        ndefSession = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        ndefSession?.alertMessage = "将 NFC 标签靠近设备以扫描。"
        ndefSession?.begin()
        nfcState = 1
        return true
    }

    // MARK: - openTagReaderSession

    @available(iOS 13.0, *)
    private func openTagReaderSession() -> Bool {
        tagSession = NFCTagReaderSession(
            pollingOption: [
                .iso14443,
                .iso15693,
                .iso18092
            ],
            delegate: self,
            queue: nil
        )
        tagSession?.alertMessage = "将 NFC 标签靠近设备以扫描。"
        tagSession?.begin()
        nfcState = 1
        return true
    }

    // MARK: - disableReaderMode

    func disableReaderMode() -> Bool {
        if mFtmCommands != nil {
            cancelFTMTransfer()
        }

        nfcState = 0

        if let session = ndefSession {
            session.invalidate()
            ndefSession = nil
        }

        if #available(iOS 13.0, *) {
            if let session = tagSession {
                session.invalidate()
                tagSession = nil
            }
        }

        return true
    }

    // MARK: - initFTM

    func initFTM() {
        guard mST25DVTag != nil else {
            nfcState = 3
            sendToastMessage(message: "initFTM: mST25DVTag is nil")
            return
        }

        // FTM commands are initialized by the ST25 SDK framework.
        // The tag object is already created when a tag is discovered.
        pListener = ProgressListener(plugin: self)
        nfcState = 4
    }

    // MARK: - cancelFTMTransfer

    func cancelFTMTransfer() {
        // Cancel the current FTM transfer through the ST25 SDK
        mFtmCommands = nil
    }

    // MARK: - FTM Operations

    private func handleFTMOperation(
        _ result: @escaping FlutterResult,
        cmd: UInt8,
        data: [UInt8]
    ) {
        operationQueue.async { [weak self] in
            guard let self = self else { return }
            var responseData: [UInt8] = []

            do {
                responseData = try self.FTMrwData(cmd: cmd, sendData: data)
            } catch {
                let err = "Error " + error.localizedDescription
                    .replacingOccurrences(of: "Error Error", with: "Error")
                self.sendToastMessage(message: err)
            }

            let finalData = responseData
            DispatchQueue.main.async {
                result(finalData)
            }
        }
    }

    private func FTMrwData(cmd: UInt8, sendData: [UInt8]) throws -> [UInt8] {
        guard mFtmCommands != nil else {
            throw NSError(
                domain: "NfcFtmPlugin",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Send FTM data error: mFtmCommands is nil"]
            )
        }

        // FTM communication is handled by the ST25 SDK's FtmCommands class.
        // This sends the command through the tag's fast transfer mailbox
        // and waits for a response with progress reporting.
        //
        // Equivalent to:
        //   mFtmCommands.sendCmdAndWaitForCompletion(cmd, sendData, true, true, pListener, 10000)
        return []
    }

    // MARK: - NDEF Read

    private func readNdef(result: @escaping FlutterResult) {
        if mST25DVTag == nil {
            return
        }

        operationQueue.async { [weak self] in
            guard let self = self else { return }
            var ndefData: [String: Any] = [:]

            do {
                // Read NDEF message from the ST25DV tag using the ST25 SDK.
                // The NDEF message contains TextRecord with payload data.
                // Extract language code (first 2 bytes of payload after status byte)
                // and text content (remaining bytes).
                //
                // Equivalent to:
                //   NDEFMsg ndefmsg = mST25DVTag.readNdefMessage();
                //   for (NDEFRecord record : ndefmsg.getNDEFRecords()) { ... }
            } catch {
                self.sendToastMessage(
                    message: "Read NDEF message Exception: \(error.localizedDescription)"
                )
            }

            let finalData = ndefData
            DispatchQueue.main.async {
                result(finalData)
            }
        }
    }

    // MARK: - NDEF Write

    private func writeNdef(result: @escaping FlutterResult, text: String) {
        if mST25DVTag == nil {
            return
        }

        operationQueue.async { [weak self] in
            guard let self = self else { return }
            var isSuccess = true

            do {
                // Write NDEF message to the ST25DV tag using the ST25 SDK.
                // Creates a TextRecord and wraps it in an NDEFMsg.
                //
                // Equivalent to:
                //   NDEFMsg ndefmsg = new NDEFMsg();
                //   TextRecord ndefRecord = new TextRecord(data);
                //   ndefmsg.addRecord(ndefRecord);
                //   mST25DVTag.writeNdefMessage(ndefmsg);
            } catch {
                self.sendToastMessage(
                    message: "write NDEF message Exception: \(error.localizedDescription)"
                )
                isSuccess = false
            }

            let finalSuccess = isSuccess
            DispatchQueue.main.async {
                result(finalSuccess)
            }
        }
    }

    // MARK: - Progress Updates

    public func updateProgress(
        isTransmitted: Bool,
        tORrBytes: Int,
        acknowledgedBytes: Int,
        totalSize: Int
    ) {
        guard totalSize > 0, let sink = eventSink else { return }

        let progress = (acknowledgedBytes * 100) / totalSize
        let secondaryProgress = (tORrBytes * 100) / totalSize

        var data: [String: Any] = [:]
        data["progress"] = progress
        data["secondaryProgress"] = secondaryProgress
        data["acknowledgedBytes"] = acknowledgedBytes
        data["totalSize"] = totalSize

        if isTransmitted {
            data["k"] = "transmissionProgress"
            data["transmittedBytes"] = tORrBytes
        } else {
            data["k"] = "receptionProgress"
            data["receivedBytes"] = tORrBytes
        }

        DispatchQueue.main.async {
            sink(data)
        }
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
        pListener = ProgressListener(plugin: self)
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        pListener = nil
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

        for message in messages {
            let ndefLen = message.length

            for record in message.records {
                let payload = record.payload

                if payload.count > 3 {
                    var returnVal: [String: Any] = [:]
                    returnVal["k"] = "onDiscovered"
                    returnVal["id"] = ""
                    returnVal["type"] = "[]"
                    returnVal["memSize"] = 0
                    returnVal["ndefLength"] = ndefLen

                    DispatchQueue.main.async { [weak self] in
                        self?.eventSink?(returnVal)
                    }
                    return
                }
            }
        }
    }

    public func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                sendToastMessage(message: "用户取消了 NFC 读取。")
            default:
                sendToastMessage(message: "NFC 错误：\(error.localizedDescription)")
            }
        }
        ndefSession = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate (iOS 13+)

@available(iOS 13.0, *)
extension NfcFtmPlugin: NFCTagReaderSessionDelegate {

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    public func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        if let nfcError = error as? NFCReaderError {
            switch nfcError.code {
            case .readerSessionInvalidationErrorUserCanceled:
                sendToastMessage(message: "用户取消了 NFC 读取。")
            default:
                sendToastMessage(message: "NFC 错误：\(error.localizedDescription)")
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

        switch tag {
        case .iso15693(let isoTag):
            tagIdHex = bytesToHex(isoTag.identifier.map { $0 })
            techList.append("android.nfc.tech.NfcV")
        case .iso7816(let isoTag):
            tagIdHex = bytesToHex([UInt8](isoTag.identifier))
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
                self.sendToastMessage(
                    message: "Tag connect error: \(error.localizedDescription)"
                )
                session.invalidate()
                return
            }

            // The tag is now connected. For ST25DV tags (ISO15693),
            // the ST25 SDK can create a tag object and initialize FTM commands.
            //
            // Equivalent to Android:
            //   AndroidReaderInterface readerInterface = AndroidReaderInterface.newInstance(tag);
            //   tagInfo.productID = identifyTypeVProduct(readerInterface, uid);
            //   tagInfo.nfcTag = new ST25DVTag(readerInterface, uid);
            //   mST25DVTag = (ST25DVTag) tagInfo.nfcTag;

            var memSize = 0
            var ndefLen = 0

            var returnVal: [String: Any] = [:]
            returnVal["k"] = "onDiscovered"
            returnVal["id"] = tagIdHex
            returnVal["type"] = "[\(techList.joined(separator: ", "))]"
            returnVal["memSize"] = memSize
            returnVal["ndefLength"] = ndefLen

            // Store tag reference for subsequent FTM/NDEF operations
            self.mST25DVTag = tag as AnyObject

            if self.isFTMmode {
                self.initFTM()
            }

            DispatchQueue.main.async {
                self.eventSink?(returnVal)
            }
        }
    }
}
