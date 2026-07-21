import Foundation
import CoreNFC
import st25sdkFramework

@available(iOS 13.0, *)
class iOSNdef: NSObject {

    private var mResponseBuffer: NFCNDEFMessage?
    private var mCommandError: Error?
    private var mSemaphoreFunction: DispatchSemaphore = DispatchSemaphore(value: 1)
    private var mSemaphoreBuffer: DispatchSemaphore = DispatchSemaphore(value: 0)

    private var mTag: NFCNDEFTag
    private let mSession: NFCTagReaderSession

    init(_ tag: NFCNDEFTag, session: NFCTagReaderSession) {
        self.mTag = tag
        self.mSession = session
        super.init()
    }

    private func semaphoreFunctionWait() { mSemaphoreFunction.wait() }
    private func semaphoreFunctionSignal() { mSemaphoreFunction.signal() }
    private func semaphoreBufferWait() { mSemaphoreBuffer.wait() }
    private func semaphoreBufferSignal() { mSemaphoreBuffer.signal() }

    private func completionHandler(_ message: NFCNDEFMessage?, _ error: Error?) {
        mResponseBuffer = message
        mCommandError = error
        semaphoreBufferSignal()
    }

    func readNdef() -> NFCNDEFMessage? {
        semaphoreFunctionWait()
        mTag.readNDEF { [weak self] message, error in
            self?.completionHandler(message, error)
            self?.semaphoreFunctionSignal()
        }
        semaphoreBufferWait()
        return mResponseBuffer
    }

    func writeNdef(_ message: NFCNDEFMessage) -> Error? {
        semaphoreFunctionWait()
        mTag.writeNDEF(message) { [weak self] error in
            self?.completionHandler(nil, error)
            self?.semaphoreFunctionSignal()
        }
        semaphoreBufferWait()
        return mCommandError
    }

    static func buildTextNDEFMessage(text: String, lang: String = "en") -> NFCNDEFMessage? {
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

    static func parseTextFromNDEF(_ message: NFCNDEFMessage) -> (lang: String, text: String, payload: Data)? {
        for record in message.records {
            let payload = record.payload
            guard payload.count > 1 else { continue }
            let langLen = Int(payload[0] & 0x3F)
            let isUtf16 = (payload[0] & 0x80) != 0
            guard payload.count > 1 + langLen else { continue }
            let langBytes = payload.subdata(in: 1..<(1 + langLen))
            let valueBytes = payload.subdata(in: (1 + langLen)..<payload.count)
            let langStr = String(data: langBytes, encoding: .ascii) ?? ""
            let textStr: String
            if isUtf16 {
                textStr = String(data: valueBytes, encoding: .utf16) ?? ""
            } else {
                textStr = String(data: valueBytes, encoding: .utf8) ?? ""
            }
            return (langStr, textStr, payload)
        }
        return nil
    }
}
