import Foundation
import CoreNFC
import st25sdkFramework

private let ISO15693_HEADER_SIZE_UID: Int = 10

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
        let cmdStr = commandName ?? "nil"
        let flag = Int(raw[0])
        let cmd = Int(raw[1])
        var reqFlags: NFCISO15693RequestFlag = []
        if (flag & 0x20) != 0 { reqFlags.insert(.address) }
        if (flag & 0x02) != 0 { reqFlags.insert(.highDataRate) }

        let result: IOSByteArray

        switch commandName {
        case "getSystemInfo":
            result = syncGetSystemInfo()

         case "readSingleBlock":
             let blockAddr = raw[ISO15693_HEADER_SIZE_UID]
             result = syncReadSingleBlock(reqFlags: reqFlags, blockAddr: blockAddr)

         case "writeSingleBlock":
             let blockAddr = raw[ISO15693_HEADER_SIZE_UID]
             let dataOffset = ISO15693_HEADER_SIZE_UID + 1
             let blockData = raw.subdata(in: dataOffset..<raw.count)
             result = syncWriteSingleBlock(reqFlags: reqFlags, blockAddr: blockAddr, data: blockData)

         case "readMultipleBlock":
             let blockAddr = Int(raw[ISO15693_HEADER_SIZE_UID])
             let blockCount = Int(raw[raw.count - 1])
             result = syncReadMultipleBlock(reqFlags: reqFlags, blockAddr: blockAddr, blockCount: blockCount)

         case "writeMultipleBlock":
             let blockAddr = Int(raw[ISO15693_HEADER_SIZE_UID])
             let blockCount = Int(raw[raw.count - 1])
             let dataOffset = ISO15693_HEADER_SIZE_UID + 1
             let writeData = raw.subdata(in: dataOffset..<(raw.count - 1))
             result = syncWriteMultipleBlock(reqFlags: reqFlags, blockAddr: blockAddr, blockCount: blockCount, data: writeData)

        case "readSingleBlockVicinity",
             "readMultipleBlockVicinity":
            let body = raw.subdata(in: 2..<raw.count)
            result = syncSendReq(flags: flag, cmd: cmd, body: body)

        case "extendedGetSystemInfo",
             "getSystemInfoVicinity":
            result = syncGetSystemInfo()

        case "readDynConfig", "readConfig", "writeDynConfig", "writeConfig",
             "presentPwd", "writePwd", "writeMsg", "readMsg", "readMsgLength":
            let body = raw.subdata(in: 2..<raw.count)
            result = syncCustomCmd(reqFlags: reqFlags, cmd: cmd, body: body)

        default:
            result = IOSByteArray(nsData: Data([0x01, 0x0F]))!
        }

        let respHex = (result.toNSData() ?? Data()).map { String(format: "%02X", $0) }.joined()
        return result
    }

     // MARK: - readSingleBlock (CoreNFC native)

     private func syncReadSingleBlock(reqFlags: NFCISO15693RequestFlag, blockAddr: UInt8) -> IOSByteArray {
         let sem = DispatchSemaphore(value: 0)
         var result: IOSByteArray?
         isoTag.readSingleBlock(requestFlags: reqFlags, blockNumber: blockAddr) { data, error in
             if error != nil {
                 result = IOSByteArray(nsData: Data([0x01, 0x0F]))
             } else {
                 var resp = Data([0x00])
                 resp.append(data)
                 result = IOSByteArray(nsData: resp)
             }
             sem.signal()
         }
         sem.wait()
         return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
     }

     // MARK: - writeSingleBlock (CoreNFC native)

     private func syncWriteSingleBlock(reqFlags: NFCISO15693RequestFlag, blockAddr: UInt8, data: Data) -> IOSByteArray {
         let sem = DispatchSemaphore(value: 0)
         var result: IOSByteArray?
         isoTag.writeSingleBlock(requestFlags: reqFlags, blockNumber: blockAddr, dataBlock: data) { error in
             if error != nil {
                 result = IOSByteArray(nsData: Data([0x01, 0x0F]))
             } else {
                 result = IOSByteArray(nsData: Data([0x00]))
             }
             sem.signal()
         }
         sem.wait()
         return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
     }

     // MARK: - readMultipleBlock (CoreNFC native)

     private func syncReadMultipleBlock(reqFlags: NFCISO15693RequestFlag, blockAddr: Int, blockCount: Int) -> IOSByteArray {
         let sem = DispatchSemaphore(value: 0)
         var result: IOSByteArray?
         isoTag.readMultipleBlocks(requestFlags: reqFlags, blockRange: NSMakeRange(blockAddr, blockCount)) { blocks, error in
             if error != nil {
                 result = IOSByteArray(nsData: Data([0x01, 0x0F]))
             } else {
                 var resp = Data([0x00])
                 for b in blocks { resp.append(b) }
                 result = IOSByteArray(nsData: resp)
             }
             sem.signal()
         }
         sem.wait()
         return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
     }

     // MARK: - writeMultipleBlock (CoreNFC native)

     private func syncWriteMultipleBlock(reqFlags: NFCISO15693RequestFlag, blockAddr: Int, blockCount: Int, data: Data) -> IOSByteArray {
         let sem = DispatchSemaphore(value: 0)
         var result: IOSByteArray?
         let range = NSMakeRange(blockAddr, blockCount)
         var blocks: [Data] = []
         let blockSize = data.count / max(blockCount, 1)
         for i in 0..<blockCount {
             let start = i * blockSize
             if start < data.count {
                 blocks.append(data.subdata(in: start..<min(start + blockSize, data.count)))
             }
         }
         isoTag.writeMultipleBlocks(requestFlags: reqFlags, blockRange: range, dataBlocks: blocks) { error in
             if error != nil {
                 result = IOSByteArray(nsData: Data([0x01, 0x0F]))
             } else {
                 result = IOSByteArray(nsData: Data([0x00]))
             }
             sem.signal()
         }
         sem.wait()
         return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
     }

    // MARK: - sendRequest (for standard commands like 0x3B, 0x2B vicinity)

    private func syncSendReq(flags: Int, cmd: Int, body: Data) -> IOSByteArray {
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?

        let uidLen = 8
        let params = body.count > uidLen ? body.subdata(in: uidLen..<body.count) : Data()

        if #available(iOS 14.0, *) {
            isoTag.sendRequest(requestFlags: flags, commandCode: cmd, data: params) { res in
                switch res {
                case .success((let respFlag, let response)):
                    var respData = Data([respFlag.rawValue])
                    if let r = response {
                        respData.append(r)
                    }
                    result = IOSByteArray(nsData: respData)
                case .failure:
                    result = IOSByteArray(nsData: Data([0x01, 0x0F]))
                @unknown default:
                    result = IOSByteArray(nsData: Data([0x01, 0x0F]))
                }
                sem.signal()
            }
        } else {
            result = IOSByteArray(nsData: Data([0x01, 0x0F]))
            sem.signal()
        }

        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
    }

    // MARK: - Custom command (strips SDK's UID, uses CoreNFC's)

    private func syncCustomCmd(reqFlags: NFCISO15693RequestFlag, cmd: Int, body: Data) -> IOSByteArray {
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?

        let isConfigCmd = (cmd == 0xA0 || cmd == 0xA1 || cmd == 0xAD || cmd == 0xAE)
        let isPwdCmd = (cmd == 0xB2 || cmd == 0xB3 || cmd == 0xB4 || cmd == 0xB5)
        let isMailboxCmd = (cmd == 0xAA || cmd == 0xAC || cmd == 0xAB)

        var params = Data()
        if isMailboxCmd {
            params = body
        } else {
            let hasPrefixByte = isConfigCmd || isPwdCmd
            let uidLen = 8
            let prefixLen = hasPrefixByte ? 1 : 0
            let totalIncludingUid = prefixLen + uidLen

            if body.count > totalIncludingUid {
                if prefixLen > 0 {
                    params.append(body[0])
                }
                params.append(body.subdata(in: totalIncludingUid..<body.count))
            } else {
                params = body
            }
        }

        if #available(iOS 14.0, *) {
            isoTag.sendRequest(requestFlags: 0x02, commandCode: cmd, data: params) { res in
                switch res {
                case .success((let respFlag, let response)):
                    var respData = Data([respFlag.rawValue])
                    if let r = response {
                        respData.append(r)
                    }
                    result = IOSByteArray(nsData: respData)
                case .failure:
                    result = IOSByteArray(nsData: Data([0x01, 0x0F]))
                @unknown default:
                    result = IOSByteArray(nsData: Data([0x01, 0x0F]))
                }
                sem.signal()
            }
        } else {
            result = IOSByteArray(nsData: Data([0x01, 0x0F]))
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
    }

    // MARK: - getSystemInfo

    private func syncGetSystemInfo() -> IOSByteArray {
        let sem = DispatchSemaphore(value: 0)
        var result: IOSByteArray?
        isoTag.getSystemInfo(requestFlags: [.address, .highDataRate]) { dfsid, afi, blockSize, totalBlocks, icRef, error in
            if let _ = error as? NFCReaderError {
                result = IOSByteArray(nsData: Data([0x01, 0x0F]))
            } else {
                var resp = Data([0x00, 0x0F])
                resp.append(Data(self.isoTag.identifier))
                resp.append(UInt8(dfsid))
                resp.append(UInt8(afi))
                resp.append(UInt8(min(Int(totalBlocks - 1), 255)))
                resp.append(UInt8(blockSize & 0xFF))
                resp.append(UInt8(icRef & 0xFF))
                result = IOSByteArray(nsData: resp)
            }
            sem.signal()
        }
        sem.wait()
        return result ?? IOSByteArray(nsData: Data([0x01, 0x0F]))!
    }

    // MARK: - Protocol stubs

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
