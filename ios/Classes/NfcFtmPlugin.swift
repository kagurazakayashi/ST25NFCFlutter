import Flutter
import UIKit
import CoreNFC

import Foundation
import CoreNFC

// MARK: - CRC32 (MPEG-2, matching ST25 SDK)

func stFTMCRC32(_ data: Data) -> UInt32 {
    let polynomial: UInt32 = 0x04C11DB7
    var crc: UInt32 = 0xFFFFFFFF
    for i in 0..<data.count {
        var word: UInt32 = UInt32(data[i])
        word <<= 24
        for _ in 0..<8 {
            if (crc ^ word) & 0x80000000 != 0 {
                crc = ((crc << 1) ^ polynomial) & 0xFFFFFFFF
            } else {
                crc = crc << 1
            }
            word <<= 1
        }
    }
    return crc
}

// MARK: - ST25DV ISO 15693 Custom Command Codes

enum StCmd: UInt8 {
    case writeMessage       = 0xAA
    case readMessageLength  = 0xAB
    case readMessage        = 0xAC
    case readDynConfig      = 0xAD
    case writeDynConfig     = 0xAE
}

// MARK: - FTM Protocol Constants

enum FtmConst {
    static let chainedHeaderSize     = 13
    static let simpleHeaderSize      = 5

    static let transferCommand: UInt8   = 0
    static let transferAnswer: UInt8    = 1
    static let transferAck: UInt8       = 2
    static let transferOk: UInt8        = 0
    static let transferError: UInt8     = 1

    static let functionBasicTransfer: UInt8 = 3

    static let mailboxSize           = 256
    static let pollIntervalMs        = 80
    static let timeoutMs             = 10000
}

// MARK: - Mailbox helpers

@available(iOS 13.0, *)
class FtmMailbox {
    let isoTag: NFCISO15693Tag

    init(isoTag: NFCISO15693Tag) {
        self.isoTag = isoTag
    }

    func writeMessage(_ data: Data) async throws {
        let sizeByte = UInt8(data.count - 1)
        var params = Data([sizeByte])
        params.append(data)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            isoTag.customCommand(requestFlags: [.highDataRate],
                                 customCommandCode: Int(StCmd.writeMessage.rawValue),
                                 customRequestParameters: params) { response, error in
                if let error = error {
                    let nsError = error as NSError
                    cont.resume(throwing: NSError(domain: "FTM", code: nsError.code,
                        userInfo: [NSLocalizedDescriptionKey: "WriteMsg err[\(nsError.code)]: \(nsError.localizedDescription)"]))
                } else if response.isEmpty || response[0] == 0x00 {
                    cont.resume()
                } else {
                    cont.resume(throwing: NSError(domain: "FTM", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WriteMsg resp[0]=0x\(String(response[0], radix: 16))"]))
                }
            }
        }
    }

    func readMessageLength() async throws -> Int {
        try await withCheckedThrowingContinuation { cont in
            isoTag.customCommand(requestFlags: [.highDataRate],
                                 customCommandCode: Int(StCmd.readMessageLength.rawValue),
                                 customRequestParameters: Data()) { response, error in
                if let error = error {
                    let nsError = error as NSError
                    cont.resume(throwing: NSError(domain: "FTM", code: nsError.code,
                        userInfo: [NSLocalizedDescriptionKey: "rdMLen err[\(nsError.code)]: \(nsError.localizedDescription)"]))
                } else if response.count >= 1 {
                    cont.resume(returning: Int(response[0]) + 1)
                } else {
                    cont.resume(throwing: NSError(domain: "FTM", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "rdMLen empty resp"]))
                }
            }
        }
    }

    func readMessage(offset: UInt8, size: UInt8) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            isoTag.customCommand(requestFlags: [.highDataRate],
                                 customCommandCode: Int(StCmd.readMessage.rawValue),
                                 customRequestParameters: Data([offset, size])) { response, error in
                if let error = error {
                    let nsError = error as NSError
                    cont.resume(throwing: NSError(domain: "FTM", code: nsError.code,
                        userInfo: [NSLocalizedDescriptionKey: "rdMsg err[\(nsError.code)]: \(nsError.localizedDescription)"]))
                } else if !response.isEmpty {
                    cont.resume(returning: response)
                } else {
                    cont.resume(throwing: NSError(domain: "FTM", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "rdMsg empty resp"]))
                }
            }
        }
    }

    func readMailboxMessage() async throws -> Data {
        let len = try await readMessageLength()
        guard len > 0 else {
            throw NSError(domain: "FTM", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Mailbox message length is 0"])
        }
        var result = Data()
        var offset: UInt8 = 0
        while offset < len {
            let remaining = len - Int(offset)
            let chunkSize = UInt8(min(remaining, Int(FtmConst.mailboxSize)))
            let chunk = try await readMessage(offset: offset, size: chunkSize)
            guard !chunk.isEmpty else {
                throw NSError(domain: "FTM", code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid mailbox read response"])
            }
            result.append(chunk)
            offset += UInt8(chunk.count)
        }
        return result
    }

    func readDynConfig(register: UInt8) async throws -> UInt8 {
        try await withCheckedThrowingContinuation { cont in
            isoTag.customCommand(requestFlags: [.highDataRate],
                                 customCommandCode: Int(StCmd.readDynConfig.rawValue),
                                 customRequestParameters: Data([register])) { response, error in
                if let error = error {
                    let nsError = error as NSError
                    cont.resume(throwing: NSError(domain: "FTM", code: nsError.code,
                        userInfo: [NSLocalizedDescriptionKey: "rdCfg err[\(nsError.code)]: \(nsError.localizedDescription)"]))
                } else if response.count >= 1 {
                    cont.resume(returning: response[0])
                } else {
                    cont.resume(throwing: NSError(domain: "FTM", code: -6,
                        userInfo: [NSLocalizedDescriptionKey: "rdCfg empty resp"]))
                }
            }
        }
    }

    func writeDynConfig(register: UInt8, value: UInt8) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            isoTag.customCommand(requestFlags: [.highDataRate],
                                 customCommandCode: Int(StCmd.writeDynConfig.rawValue),
                                 customRequestParameters: Data([register, value])) { response, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    func hasHostPutMsg() async throws -> Bool {
        let ctrl = try await readDynConfig(register: 0x00)
        return (ctrl & 0x01) != 0
    }

    func hasRFPutMsg() async throws -> Bool {
        let ctrl = try await readDynConfig(register: 0x00)
        return (ctrl & 0x02) != 0
    }
}

// MARK: - FTM Transfer Task

@available(iOS 13.0, *)
class FtmTransferTask {
    let mailbox: FtmMailbox
    var onTransmissionProgress: ((Int, Int, Int, Int, Int) -> Void)?
    var onReceptionProgress: ((Int, Int, Int, Int, Int) -> Void)?

    init(mailbox: FtmMailbox) {
        self.mailbox = mailbox
    }

    func sendCommandAndWait(_ cmd: UInt8, data: Data) async throws -> Data {
        let requestPayload = Data([cmd]) + data
        return try await uploadAndDownload(requestPayload)
    }

    private func buildChainedHeader(payloadLen: Int, totalSize: Int, chunkIndex: Int, totalChunks: Int, function: UInt8) -> Data {
        var frame = Data(count: FtmConst.chainedHeaderSize)
        frame[0] = function
        frame[1] = FtmConst.transferCommand
        frame[2] = FtmConst.transferOk
        frame[3] = 0x01
        frame[4] = UInt8((totalSize >> 24) & 0xFF)
        frame[5] = UInt8((totalSize >> 16) & 0xFF)
        frame[6] = UInt8((totalSize >> 8) & 0xFF)
        frame[7] = UInt8(totalSize & 0xFF)
        frame[8] = UInt8((totalChunks >> 8) & 0xFF)
        frame[9] = UInt8(totalChunks & 0xFF)
        frame[10] = UInt8((chunkIndex >> 8) & 0xFF)
        frame[11] = UInt8(chunkIndex & 0xFF)
        frame[12] = UInt8(payloadLen & 0xFF)
        return frame
    }

    private func buildCrcFrame(crc: UInt32, function: UInt8) -> Data {
        var frame = Data(count: 9)
        frame[0] = function
        frame[1] = FtmConst.transferAck
        frame[2] = 0x00
        frame[3] = 0x00
        frame[4] = 0x04
        frame[5] = UInt8((crc >> 24) & 0xFF)
        frame[6] = UInt8((crc >> 16) & 0xFF)
        frame[7] = UInt8((crc >> 8) & 0xFF)
        frame[8] = UInt8(crc & 0xFF)
        return frame
    }

    private func buildAckFrame(ok: Bool, function: UInt8) -> Data {
        var frame = Data(count: 5)
        frame[0] = function
        frame[1] = FtmConst.transferAck
        frame[2] = ok ? FtmConst.transferOk : FtmConst.transferError
        frame[3] = 0x00
        frame[4] = 0x00
        return frame
    }

    private func uploadAndDownload(_ payload: Data) async throws -> Data {
        let function = FtmConst.functionBasicTransfer

        let maxPayload = FtmConst.mailboxSize - FtmConst.chainedHeaderSize
        let totalChunks = max((payload.count + maxPayload - 1) / maxPayload, 1)
        let totalSize = payload.count

        if try await mailbox.hasHostPutMsg() {
            throw NSError(domain: "FTM", code: -30,
                userInfo: [NSLocalizedDescriptionKey: "Mailbox occupied, previous message not consumed by MCU"])
        }

        // Step 1: Upload chunks
        var offset = 0
        var chunkIndex = 1
        while offset < payload.count {
            let remaining = payload.count - offset
            let chunkSize = min(remaining, maxPayload)
            let chunkData = payload.subdata(in: offset..<offset+chunkSize)

            var header = buildChainedHeader(payloadLen: chunkSize,
                                            totalSize: totalSize,
                                            chunkIndex: chunkIndex,
                                            totalChunks: totalChunks,
                                            function: function)
            header.append(chunkData)

            try await mailbox.writeMessage(header)

            let progress = Int(Double(offset + chunkSize) / Double(totalSize) * 100)
            onTransmissionProgress?(offset + chunkSize, 0, totalSize, progress, progress)

            offset += chunkSize
            chunkIndex += 1
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        // Step 2: Wait for CRC response from MCU
        let crcResponse = try await waitForMailboxMessage()

        // Verify CRC response
        let localCrc = stFTMCRC32(payload)
        if crcResponse.count >= 9, crcResponse[4] == 0x04 {
            let remoteCrc = (UInt32(crcResponse[5]) << 24) |
                            (UInt32(crcResponse[6]) << 16) |
                            (UInt32(crcResponse[7]) << 8) |
                            UInt32(crcResponse[8])
            guard remoteCrc == localCrc else {
                throw NSError(domain: "FTM", code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "CRC mismatch: local=\(localCrc) remote=\(remoteCrc)"])
            }
        }

        // Step 3: Send ACK (OK)
        let ackFrame = buildAckFrame(ok: true, function: function)
        try await mailbox.writeMessage(ackFrame)

        // Step 4: Read response from MCU
        let response = try await waitForMailboxMessage()

        // Return response data (skip chained header)
        let responsePayload: Data
        if response.count > FtmConst.chainedHeaderSize {
            let respPayloadLen = Int(response[12] & 0xFF)
            let available = response.count - FtmConst.chainedHeaderSize
            let readLen = min(respPayloadLen, available)
            responsePayload = response.subdata(in: FtmConst.chainedHeaderSize..<(FtmConst.chainedHeaderSize + readLen))
        } else {
            responsePayload = response
        }

        return responsePayload
    }

    private func waitForMailboxMessage() async throws -> Data {
        let startTime = Date()
        while true {
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            if elapsed > Double(FtmConst.timeoutMs) {
                throw NSError(domain: "FTM", code: -20,
                    userInfo: [NSLocalizedDescriptionKey: "FTM timeout waiting for response"])
            }

            do {
                if try await mailbox.hasHostPutMsg() {
                    return try await mailbox.readMailboxMessage()
                }
            } catch let err as NFCReaderError {
                if err.errorCode == NFCReaderError.Code.readerSessionInvalidationErrorSessionTerminatedUnexpectedly.rawValue {
                    throw err
                }
            } catch {
                // Ignore polling errors, keep trying
            }

            try await Task.sleep(nanoseconds: UInt64(FtmConst.pollIntervalMs) * 1_000_000)
        }
    }
}


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
    private var mFTmIsoTag: NFCISO15693Tag?
    private var mFtmCommands: AnyObject?

    // MARK: - Progress listener

    private var pListener: ProgressListener?

    // MARK: - Operation queue

    private let operationQueue = DispatchQueue(label: "com.nfcftm.ios.operation")

    // MARK: - Pending operation (lazy session start)

    private var pendingOp: PendingOperation?

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
        sendToastMessage(message: "isEnabledNFC: \(available)")
        result(available)
    }

    // MARK: - openNFC

    private func handleOpenNFC(_ result: @escaping FlutterResult) {
        isFTMmode = false
        if mFtmCommands != nil {
            cancelFTMTransfer()
            mFtmCommands = nil
        }
        nfcState = 1
        result(true)
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
        nfcState = 1
        result(true)
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
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        let dataBytes = [UInt8](sendData.data)
        startFTMSession(result: result, cmd: NfcFtmPlugin.FTM_CMD_SEND_DATA, data: dataBytes)
    }

    // MARK: - readFTMData

    private func handleReadFTMData(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rsendData = args["data"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "data required", details: nil))
            return
        }
        let dataBytes = [UInt8](rsendData.data)
        startFTMSession(result: result, cmd: NfcFtmPlugin.FTM_CMD_READ_DATA, data: dataBytes)
    }

    // MARK: - FTMcancel

    private func handleFTMcancel(_ result: @escaping FlutterResult) {
        if mFtmCommands == nil { return }
        cancelFTMTransfer()
    }

    // MARK: - NDEF@read

    private func handleNDEFRead(_ result: @escaping FlutterResult) {
        startNDEFReadSession(result: result)
    }

    // MARK: - NDEF@write

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
        if #unavailable(iOS 11.0) {
            sendToastMessage(message: "Requires iOS 11.0 or above")
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

    @available(iOS 13.0, *)
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
        if #available(iOS 13.0, *) {
            startFTMSessionViaTagReader(result: result, cmd: cmd, data: data)
        } else {
            sendToastMessage(message: "FTM requires iOS 13.0+")
            result([])
        }
    }

    // MARK: - disableReaderMode

    func disableReaderMode() -> Bool {
        if mFtmCommands != nil {
            cancelFTMTransfer()
        }
        nfcState = 0
        pendingOp = nil

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
        pListener = ProgressListener(plugin: self)
        nfcState = 4
    }

    // MARK: - cancelFTMTransfer

    func cancelFTMTransfer() {
        mFtmCommands = nil
    }

    // MARK: - FTM Operations

    @available(iOS 13.0, *)
    private func performFTMOperation(
        cmd: UInt8,
        data: [UInt8],
        isoTag: NFCISO15693Tag,
        session: NFCTagReaderSession,
        result: @escaping FlutterResult
    ) {
        let mailbox = FtmMailbox(isoTag: isoTag)
        let task = FtmTransferTask(mailbox: mailbox)

        task.onTransmissionProgress = { [weak self] transmitted, acknowledged, total, progress, secondary in
            self?.sendProgressUpdate(isTransmitted: true,
                                     tORrBytes: transmitted,
                                     acknowledgedBytes: acknowledged,
                                     totalSize: total)
        }
        task.onReceptionProgress = { [weak self] received, acknowledged, total, progress, secondary in
            self?.sendProgressUpdate(isTransmitted: false,
                                     tORrBytes: received,
                                     acknowledgedBytes: acknowledged,
                                     totalSize: total)
        }

        _ = Task { [weak self] in
            do {
                let ctrl = try await mailbox.readDynConfig(register: 0x00)
                self?.sendToastMessage(message: "FTM pre-flight: dynConfig[0x00]=0x\(String(ctrl, radix: 16))")
                let response = try await task.sendCommandAndWait(cmd, data: Data(data))
                self?.sendProgressUpdate(isTransmitted: false,
                                         tORrBytes: response.count,
                                         acknowledgedBytes: response.count,
                                         totalSize: response.count)
                session.invalidate()
                DispatchQueue.main.async { result([UInt8](response)) }
            } catch {
                self?.sendToastMessage(message: "FTM error: \(error.localizedDescription)")
                session.invalidate()
                DispatchQueue.main.async { result([]) }
            }
        }
    }

    private func sendProgressUpdate(isTransmitted: Bool, tORrBytes: Int, acknowledgedBytes: Int, totalSize: Int) {
        guard let sink = eventSink else { return }
        let progress: Int = totalSize > 0 ? (acknowledgedBytes * 100) / totalSize : 0
        let secondaryProgress: Int = totalSize > 0 ? (tORrBytes * 100) / totalSize : 0
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
        DispatchQueue.main.async { sink(data) }
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

        // Build UTF-8 Text Record payload for compatibility with Android
        let textPayload = buildUTF8TextNDEFPayload(text: text)
        let payload = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: Data([0x54]), // "T" for Text Record
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
        DispatchQueue.main.async { sink(data) }
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

        guard let op = pendingOp else {
            // Tag discovered event — always send even if no NDEF data
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
            break
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
                self.sendToastMessage(message: "Tag connect error: \(error.localizedDescription)")
                self.finishPendingOp(withError: error.localizedDescription)
                session.invalidate()
                return
            }

            // Store tag reference
            self.mST25DVTag = tag as AnyObject

            if self.isFTMmode {
                self.initFTM()
            }

            // Handle pending operation BEFORE event dispatch (keep connection alive)
            if let op = self.pendingOp {
                self.pendingOp = nil
                switch op {
                case .ndefWrite(let result, let text):
                    if case .iso15693(let isoTag) = tag {
                        self.writeNDEFViaNDEFTag(to: isoTag, text: text, session: session, result: result)
                    } else {
                        self.sendToastMessage(message: "Tag does not support NDEF write")
                        session.invalidate()
                        result(false)
                    }
                case .ftmSend(let result, let cmd, let data):
                    if case .iso15693(let isoTag) = tag {
                        self.mFTmIsoTag = isoTag
                        self.performFTMOperation(cmd: cmd, data: data, isoTag: isoTag, session: session, result: result)
                    } else {
                        session.invalidate()
                        result([])
                    }
                default:
                    session.invalidate()
                }
                return
            }

            // No pending op — send onDiscovered event then invalidate
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
