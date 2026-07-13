import Foundation
import HelperIPC

public final class HelperXPCService: NSObject, HelperToolProtocol {
    private let service: HelperService
    private let version: String

    public init(service: HelperService, version: String = "1.0.0") {
        self.service = service
        self.version = version
    }

    public func getVersion(reply: @escaping (String) -> Void) {
        reply(version)
    }

    public func getFanData(reply: @escaping (Data?, String?) -> Void) {
        do {
            let snapshots = try service.fanSnapshots()
            let payload = try HelperPayloadCodec.encodeFans(snapshots)
            reply(payload, nil)
        } catch let error as HelperServiceError {
            reply(nil, error.rawValue)
        } catch {
            reply(nil, "payload_encoding_failed")
        }
    }

    public func setFanSpeed(index: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        send(service.setFanSpeed(index: index, rpm: rpm), using: reply)
    }

    public func resetFanToAuto(index: Int, reply: @escaping (Bool, String?) -> Void) {
        send(service.resetFanToAuto(index: index), using: reply)
    }

    public func resetAllFansToAuto(reply: @escaping (Bool, String?) -> Void) {
        send(service.resetAllFansToAuto(), using: reply)
    }

    public func getTemperatures(reply: @escaping (Data?, String?) -> Void) {
        do {
            let snapshots = try service.temperatures()
            let payload = try HelperPayloadCodec.encodeTemperatures(snapshots)
            reply(payload, nil)
        } catch let error as HelperServiceError {
            reply(nil, error.rawValue)
        } catch {
            reply(nil, "payload_encoding_failed")
        }
    }

    public func removeLegacyHelper(reply: @escaping (Bool, String?) -> Void) {
        reply(false, "legacy_removal_unavailable")
    }

    private func send(_ result: HelperOperationResult, using callback: @escaping (Bool, String?) -> Void) {
        callback(result.success, result.error)
    }
}
