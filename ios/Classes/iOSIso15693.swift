import Foundation
import CoreNFC

class iOSIso15693: NSObject {

    private var mResponseBuffer: Data?
    private var mSemaphoreFunction: DispatchSemaphore = DispatchSemaphore(value: 1)
    private var mSemaphoreBuffer: DispatchSemaphore = DispatchSemaphore(value: 0)

    typealias HandlerResults = (_ responseBuffer: Data?, _ tagError: TagError?) -> Void

    private var mTag: NFCISO15693Tag
    private let mSession: NFCTagReaderSession

    var identifier: Data { mTag.identifier }

    init(_ tag: NFCISO15693Tag, session: NFCTagReaderSession) {
        self.mTag = tag
        self.mSession = session
        super.init()
    }

    // MARK: - Semaphore helpers

    private func semaphoreFunctionWait() { mSemaphoreFunction.wait() }
    private func semaphoreFunctionSignal() { mSemaphoreFunction.signal() }
    private func semaphoreBufferWait() { mSemaphoreBuffer.wait() }
    private func semaphoreBufferSignal() { mSemaphoreBuffer.signal() }

    private func completionHandler(responseRead: Data?, error: TagError?) {
        mResponseBuffer = responseRead
        semaphoreBufferSignal()
    }

    // MARK: - Error helpers

    private func createErrorResponse(error: NFCReaderError, _ location: String = "") -> Data {
        var errVal: Int = 0x0F
        if let info = error.errorUserInfo as? [String: Any],
           let code = info["ISO15693TagResponseErrorCode"] as? Int {
            errVal = code
        }
        return Data([0x01, UInt8(errVal)])
    }

    // MARK: - Buffer getter

    private func getBufferResponse() -> Data? {
        semaphoreBufferWait()
        return mResponseBuffer
    }

    // MARK: - getSystemInfo

    func getSystemInfo() -> Data? {
        semaphoreFunctionWait()
        mTag.getSystemInfo(requestFlags: [.address, .highDataRate]) { [weak self] dfsid, afi, blockSize, totalBlocks, icRef, error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "getSystemInfo"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                var resp = Data([0x00, 0x0F])
                resp.append(self.mTag.identifier)
                resp.append(UInt8(dfsid))
                resp.append(UInt8(afi))
                resp.append(UInt8(min(max(Int(totalBlocks - 1), 0), 255)))
                resp.append(UInt8(blockSize))
                resp.append(UInt8(icRef))
                self.completionHandler(responseRead: resp, error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - readSingleBlock

    func readSingleBlock(address: UInt8, flag: UInt8) -> Data? {
        let reqFlags = parseRequestFlags(flag)
        semaphoreFunctionWait()
        mTag.readSingleBlock(requestFlags: reqFlags, blockNumber: address) { [weak self] data, error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "readSingleBlock"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                var resp = Data([0x00])
                resp.append(data)
                self.completionHandler(responseRead: resp, error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - readMultipleBlocks

    func readMultipleBlocks(startBlock: UInt8, count: UInt8) -> Data? {
        semaphoreFunctionWait()
        let range = NSMakeRange(Int(startBlock), Int(count))
        mTag.readMultipleBlocks(requestFlags: [.address, .highDataRate], blockRange: range) { [weak self] blocks, error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "readMultipleBlocks"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                var resp = Data([0x00])
                for block in blocks { resp.append(block) }
                self.completionHandler(responseRead: resp, error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - writeSingleBlock

    func writeSingleBlock(address: UInt8, data: Data) -> Data? {
        semaphoreFunctionWait()
        mTag.writeSingleBlock(requestFlags: [.address, .highDataRate], blockNumber: address, dataBlock: data) { [weak self] error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "writeSingleBlock"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                self.completionHandler(responseRead: Data([0x00]), error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - writeMultipleBlocks

    func writeMultipleBlocks(startAddress: UInt8, data: Data) -> Data? {
        let chunkSize = 4
        var dataBlocks: [Data] = []
        var offset = 0
        while offset < data.count {
            let thisChunkSize = min(chunkSize, data.count - offset)
            var chunk = data.subdata(in: offset..<(offset + thisChunkSize))
            if chunk.count < chunkSize {
                var padded = [UInt8](repeating: 0, count: chunkSize)
                chunk.copyBytes(to: &padded, count: chunk.count)
                chunk = Data(padded)
            }
            dataBlocks.append(chunk)
            offset += thisChunkSize
        }
        semaphoreFunctionWait()
        let range = NSMakeRange(Int(startAddress), dataBlocks.count)
        mTag.writeMultipleBlocks(requestFlags: [.address, .highDataRate], blockRange: range, dataBlocks: dataBlocks) { [weak self] error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "writeMultipleBlocks"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                self.completionHandler(responseRead: Data([0x00]), error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - customCommand

    func customCommand(code: UInt8, data: Data, flags: NFCISO15693RequestFlag = [.highDataRate]) -> Data? {
        var cmdFlags = flags
        cmdFlags.insert(.option)
        semaphoreFunctionWait()
        mTag.customCommand(requestFlags: cmdFlags, customCommandCode: Int(code), customRequestParameters: data) { [weak self] response, error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "customCommand 0x\(String(code, radix: 16))"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                var foo = response
                foo.insert(0x00, at: 0)
                self.completionHandler(responseRead: foo, error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    func customCommandWithFlags(flags: NFCISO15693RequestFlag, code: UInt8, data: Data) -> Data? {
        semaphoreFunctionWait()
        mTag.customCommand(requestFlags: flags, customCommandCode: Int(code), customRequestParameters: data) { [weak self] response, error in
            guard let self = self else { return }
            if let nfcErr = error as? NFCReaderError {
                self.completionHandler(responseRead: self.createErrorResponse(error: nfcErr, "customCommand 0x\(String(code, radix: 16))"), error: .ResponseError(nfcErr.localizedDescription))
            } else {
                var foo = response
                foo.insert(0x00, at: 0)
                self.completionHandler(responseRead: foo, error: nil)
            }
            self.semaphoreFunctionSignal()
        }
        return getBufferResponse()
    }

    // MARK: - retryOnError

    func retryOnError(code: UInt8, data: Data, flags: NFCISO15693RequestFlag = [.highDataRate]) -> Data {
        var retry = 3
        var response: Data = Data([0x01, 0x0F])
        while retry >= 0 {
            if let r = customCommand(code: code, data: data, flags: flags) {
                response = r
                if response.first == 0x00 { break }
            }
            retry -= 1
        }
        return response
    }

    // MARK: - Flag parsing

    private func parseRequestFlags(_ flag: UInt8) -> NFCISO15693RequestFlag {
        var f: NFCISO15693RequestFlag = [.highDataRate]
        if (flag & 0x20) != 0 { f.insert(.address) }
        if (flag & 0x40) != 0 { f.insert(.option) }
        return f
    }

    static func requestFlags(from flag: UInt8) -> NFCISO15693RequestFlag {
        var f: NFCISO15693RequestFlag = [.highDataRate]
        if (flag & 0x20) != 0 { f.insert(.address) }
        if (flag & 0x40) != 0 { f.insert(.option) }
        return f
    }

    // MARK: - Session

    func sessionInvalidate() {
        semaphoreFunctionWait()
        mSession.invalidate()
        semaphoreFunctionSignal()
    }

    func sessionInvalidate(errorMessage: String) {
        semaphoreFunctionWait()
        mSession.invalidate(errorMessage: errorMessage)
        semaphoreFunctionSignal()
    }
}
