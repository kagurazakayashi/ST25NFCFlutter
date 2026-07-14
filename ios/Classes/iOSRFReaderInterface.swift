import Foundation
import CoreNFC
import st25sdkFramework

private let ISO15693_HEADER_SIZE_UID: Int = 10
private let ISO15693_CUSTOM_ST_HEADER_SIZE_UID: Int = 11

class iOSRFReaderInterface: NSObject, ComStSt25sdkRFReaderInterface {

    private let isoTag: NFCISO15693Tag
    private let session: NFCTagReaderSession

    init(isoTag: NFCISO15693Tag, session: NFCTagReaderSession) {
        self.isoTag = isoTag
        self.session = session
        super.init()
    }

    func transceive(withId obj: Any!, with commandName: String!, with data: IOSByteArray!) -> IOSByteArray! {
        let raw = data.toNSData() ?? Data()
        switch commandName {
        case "getSystemInfo":        return syncGetSystemInfo()
        case "readSingleBlock":      return syncReadSingleBlock(raw: raw)
        case "readMultipleBlock":    return syncReadMultipleBlock(raw: raw)
        case "writeMsg":             return syncWriteMsg(raw: raw)
        case "readMsgLength":        return syncCustom(cmd: 0xAB, data: Data())
        case "readMsg":              return syncReadMsg(raw: raw)
        case "readDynConfig":        return syncCustom(cmd: raw[1], data: Data([raw[raw.count - 1]]))
        case "writeDynConfig":       return syncCustom(cmd: raw[1], data: Data([raw[raw.count - 2], raw[raw.count - 1]]))
        case "readConfig":           return syncCustom(cmd: raw[1], data: raw.subdata(in: ISO15693_CUSTOM_ST_HEADER_SIZE_UID..<raw.count))
        case "writeConfig":          return syncCustom(cmd: raw[1], data: raw.subdata(in: ISO15693_CUSTOM_ST_HEADER_SIZE_UID..<raw.count))
        case "presentPwd":           return syncCustom(cmd: raw[1], data: raw.subdata(in: ISO15693_CUSTOM_ST_HEADER_SIZE_UID..<raw.count))
        case "writePwd":             return syncCustom(cmd: raw[1], data: raw.subdata(in: ISO15693_CUSTOM_ST_HEADER_SIZE_UID..<raw.count))
        default:                     return IOSByteArray(nsData: Data([0x01, 0x0F]))
        }
    }

    // MARK: - Synchronous wrappers using Task + semaphore

    private func syncGetSystemInfo() -> IOSByteArray {
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        Task {
            if let info = try? await isoTag.systemInfo(requestFlags: [.address, .highDataRate]) {
                var resp = Data()
                let flags: UInt8 = 0x0F
                resp.append(flags)
                resp.append(0x00)
                resp.append(0x00)
                resp.append(UInt8(info.blockSize & 0xFF))
                resp.append(UInt8(info.totalBlocks & 0xFF))
                resp.append(UInt8(info.icReference & 0xFF))
                result = IOSByteArray(nsData: resp)
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))
    }

    private func syncReadSingleBlock(raw: Data) -> IOSByteArray {
        let flag = Int(raw[0])
        let blockAddr = raw[ISO15693_HEADER_SIZE_UID]
        var reqFlags: NFCISO15693RequestFlag = []
        if (flag & 0x20) != 0 { reqFlags.insert(.address) }
        if (flag & 0x02) != 0 { reqFlags.insert(.highDataRate) }
        if (flag & 0x40) != 0 { reqFlags.insert(.option) }

        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        Task {
            if let data = try? await isoTag.readSingleBlock(requestFlags: reqFlags, blockNumber: blockAddr) {
                result = IOSByteArray(nsData: Data(data))
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))
    }

    private func syncReadMultipleBlock(raw: Data) -> IOSByteArray {
        let blockAddr = Int(raw[ISO15693_HEADER_SIZE_UID])
        let blockCount = Int(raw[raw.count - 1])

        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        isoTag.readMultipleBlocks(requestFlags: [.address, .highDataRate], blockRange: NSMakeRange(blockAddr, blockCount)) { blocks, err in
            if err == nil {
                var combined = Data()
                for block in blocks { combined.append(block) }
                result = IOSByteArray(nsData: combined)
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))
    }

    private func syncWriteMsg(raw: Data) -> IOSByteArray {
        let payload = raw.subdata(in: 11..<raw.count)
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        Task {
            for _ in 0..<3 {
                if let resp = try? await isoTag.customCommand(requestFlags: [], customCommandCode: 0xAA, customRequestParameters: payload),
                   resp.first == 0x00 {
                    result = IOSByteArray(nsData: Data(resp))
                    break
                }
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))
    }

    private func syncReadMsg(raw: Data) -> IOSByteArray {
        let offset = raw[raw.count - 2]
        let size = raw[raw.count - 1]
        return syncCustom(cmd: 0xAC, data: Data([offset, size]))
    }

    private func syncCustom(cmd: UInt8, data: Data) -> IOSByteArray {
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        Task {
            if let resp = try? await isoTag.customCommand(requestFlags: [], customCommandCode: Int(cmd), customRequestParameters: data) {
                result = IOSByteArray(nsData: Data(resp))
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))
    }

    // MARK: - Required protocol stubs

    func decodeTagType(with uid: IOSByteArray) -> ComStSt25sdkNFCTag_NfcTagTypes {
        return ComStSt25sdkNFCTag_NfcTagTypes.NFC_TAG_TYPE_V
    }

    func getMaxTransmitLengthInBytes() -> jint { return 246 }
    func getMaxReceiveLengthInBytes() -> jint { return 32 }
    func getTransceiveMode() -> ComStSt25sdkRFReaderInterface_TransceiveMode! { return .NORMAL }
    func getTransceivedData() -> JavaUtilList! { return nil }
    func getLastTransceivedData() -> IOSByteArray! { return nil }
    func getTechList(with uid: IOSByteArray!) -> IOSObjectArray! { return nil }
    func inventory(with mode: ComStSt25sdkRFReaderInterface_InventoryMode!) -> JavaUtilList! { return nil }
    func setTransceiveModeWith(_ mode: ComStSt25sdkRFReaderInterface_TransceiveMode!) {}
    func setTagResponseLengthInBytesWith(_ len: jint) {}
    func iso14443aSelectTag(with uid: IOSByteArray!) -> jbyte { return 0 }
    func iso14443aDeSelectTag(with uid: IOSByteArray!) -> jbyte { return 0 }
    func iso14443bSelectTag(with pupi: IOSByteArray!) -> jbyte { return 0 }
    func iso14443bDeSelectTag(with pupi: IOSByteArray!) -> jbyte { return 0 }
}
