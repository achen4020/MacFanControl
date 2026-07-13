import Foundation
@preconcurrency import HelperIPC
@preconcurrency import MacFanControlCore

final class SMCHelperClient: FanControlProvider, @unchecked Sendable {
    static let shared = SMCHelperClient()

    private enum ClientError: LocalizedError {
        case proxyUnavailable
        case helperInstallationUnavailable

        var errorDescription: String? {
            switch self {
            case .proxyUnavailable:
                return "无法建立 Helper XPC 代理"
            case .helperInstallationUnavailable:
                return "Helper 安装将在 SMAppService 接管后启用"
            }
        }
    }

    private let stateLock = NSLock()
    private var connection: NSXPCConnection?
    private var available = false

    private init() {}

    var isAvailable: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return available
    }

    func getFanData() async -> [FanDataSnapshot] {
        let gate = ReplyGate<(Data?, String?, Bool)>()
        var requestConnection: NSXPCConnection?
        do {
            let connection = try connectionForRequest()
            requestConnection = connection
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                self?.clearConnection(connection)
                gate.resolve((nil, "xpc_error", false))
            }) as? HelperToolProtocol else {
                clearConnection(connection)
                gate.resolve((nil, ClientError.proxyUnavailable.localizedDescription, false))
                return []
            }
            proxy.getFanData { data, error in
                gate.resolve((data, error, true))
            }
        } catch {
            gate.resolve((nil, error.localizedDescription, false))
        }

        let (data, error, didReply) = await gate.wait(
            timeout: .seconds(2),
            fallback: (nil, "timeout", false)
        )
        guard didReply, let requestConnection else {
            if let requestConnection { clearConnection(requestConnection) }
            return []
        }
        markRoundTripSuccessful(requestConnection)
        guard error == nil, let data,
              let snapshots = try? HelperPayloadCodec.decodeFans(data) else {
            return []
        }
        return snapshots.map {
            FanDataSnapshot(
                index: $0.index,
                currentSpeed: $0.currentRPM,
                minSpeed: $0.minimumRPM,
                maxSpeed: $0.maximumRPM,
                mode: $0.mode
            )
        }
    }

    func setFanSpeed(index: Int, rpm: Int) async -> Bool {
        await performBooleanRequest { proxy, reply in
            proxy.setFanSpeed(index: index, rpm: rpm, reply: reply)
        }
    }

    func resetFanToAuto(index: Int) async -> Bool {
        await performBooleanRequest { proxy, reply in
            proxy.resetFanToAuto(index: index, reply: reply)
        }
    }

    func resetAllFansToAuto() async -> Bool {
        await performBooleanRequest { proxy, reply in
            proxy.resetAllFansToAuto(reply: reply)
        }
    }

    func getTemperatures() async -> [HelperTemperatureSnapshot] {
        let gate = ReplyGate<(Data?, String?, Bool)>()
        var requestConnection: NSXPCConnection?
        do {
            let connection = try connectionForRequest()
            requestConnection = connection
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                self?.clearConnection(connection)
                gate.resolve((nil, "xpc_error", false))
            }) as? HelperToolProtocol else {
                clearConnection(connection)
                gate.resolve((nil, ClientError.proxyUnavailable.localizedDescription, false))
                return []
            }
            proxy.getTemperatures { data, error in
                gate.resolve((data, error, true))
            }
        } catch {
            gate.resolve((nil, error.localizedDescription, false))
        }

        let (data, error, didReply) = await gate.wait(
            timeout: .seconds(2),
            fallback: (nil, "timeout", false)
        )
        guard didReply, let requestConnection else {
            if let requestConnection { clearConnection(requestConnection) }
            return []
        }
        markRoundTripSuccessful(requestConnection)
        guard error == nil, let data,
              let snapshots = try? HelperPayloadCodec.decodeTemperatures(data) else {
            return []
        }
        return snapshots
    }

    func installHelperIfNeeded(completion: @escaping (Bool, String?) -> Void) {
        completion(false, ClientError.helperInstallationUnavailable.localizedDescription)
    }

    private func performBooleanRequest(
        _ request: (HelperToolProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) async -> Bool {
        let gate = ReplyGate<(Bool, String?, Bool)>()
        var requestConnection: NSXPCConnection?
        do {
            let connection = try connectionForRequest()
            requestConnection = connection
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                self?.clearConnection(connection)
                gate.resolve((false, "xpc_error", false))
            }) as? HelperToolProtocol else {
                clearConnection(connection)
                gate.resolve((false, ClientError.proxyUnavailable.localizedDescription, false))
                return false
            }
            request(proxy) { success, error in
                gate.resolve((success, error, true))
            }
        } catch {
            gate.resolve((false, error.localizedDescription, false))
        }

        let (success, error, didReply) = await gate.wait(
            timeout: .seconds(2),
            fallback: (false, "timeout", false)
        )
        guard didReply, let requestConnection else {
            if let requestConnection { clearConnection(requestConnection) }
            return false
        }
        markRoundTripSuccessful(requestConnection)
        guard error == nil else { return false }
        return success
    }

    private func connectionForRequest() throws -> NSXPCConnection {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let connection {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: helperMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.clearConnection(connection)
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.clearConnection(connection)
        }

        let requirement = try helperCodeSigningRequirement()
        connection.setCodeSigningRequirement(requirement)
        connection.activate()
        self.connection = connection
        return connection
    }

    private func clearConnection(_ failedConnection: NSXPCConnection) {
        stateLock.lock()
        if connection === failedConnection {
            connection = nil
            available = false
        }
        stateLock.unlock()
    }

    private func markRoundTripSuccessful(_ successfulConnection: NSXPCConnection) {
        stateLock.lock()
        if connection === successfulConnection {
            available = true
        }
        stateLock.unlock()
    }

    private func helperCodeSigningRequirement() throws -> String {
#if DEBUG && LOCAL_UNSIGNED_XPC
        NSLog("MacFanControl is using explicit local unsigned XPC mode")
        return #"identifier "com.macfancontrol.helper""#
#else
        let ownTeamID = try CurrentCodeSignature.teamIdentifier()
        return try CodeSigningRequirement(
            identifier: helperBundleIdentifier,
            teamID: ownTeamID
        ).text
#endif
    }
}
