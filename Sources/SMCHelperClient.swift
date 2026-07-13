import Foundation
@preconcurrency import HelperIPC
@preconcurrency import MacFanControlCore

final class SMCHelperClient: FanControlProvider, @unchecked Sendable {
    static let shared = SMCHelperClient()

    private enum ClientError: LocalizedError {
        case proxyUnavailable

        var errorDescription: String? {
            switch self {
            case .proxyUnavailable:
                return "无法建立 Helper XPC 代理"
            }
        }
    }

    private let connectionCreationLock = NSLock()
    private let connectionLifecycle = ConnectionLifecycle<NSXPCConnection> { connection in
        connection.invalidate()
    }

    private init() {}

    var isAvailable: Bool {
        connectionLifecycle.isAvailable
    }

    func getFanData() async -> [FanDataSnapshot] {
        let gate = ReplyGate<(Data?, String?, Bool)>()
        var requestConnection: NSXPCConnection?
        do {
            let connection = try connectionForRequest()
            requestConnection = connection
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                self?.invalidateConnection(connection)
                gate.resolve((nil, "xpc_error", false))
            }) as? HelperToolProtocol else {
                invalidateConnection(connection)
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
        guard let requestConnection,
              connectionLifecycle.acceptReply(from: requestConnection, didReply: didReply) else {
            return []
        }
        guard error == nil, let data,
              let snapshots = try? HelperPayloadCodec.decodeValidatedFans(data) else {
            invalidateConnection(requestConnection)
            return []
        }
        markRoundTripSuccessful(requestConnection)
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
                self?.invalidateConnection(connection)
                gate.resolve((nil, "xpc_error", false))
            }) as? HelperToolProtocol else {
                invalidateConnection(connection)
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
        guard let requestConnection,
              connectionLifecycle.acceptReply(from: requestConnection, didReply: didReply) else {
            return []
        }
        guard error == nil, let data,
              let snapshots = try? HelperPayloadCodec.decodeTemperatures(data) else {
            invalidateConnection(requestConnection)
            return []
        }
        markRoundTripSuccessful(requestConnection)
        return snapshots
    }

    func removeLegacyHelper() async -> Bool {
        await performBooleanRequest { proxy, reply in
            proxy.removeLegacyHelper(reply: reply)
        }
    }

    func disconnect() {
        guard let connection = connectionLifecycle.current() else { return }
        connectionLifecycle.invalidate(connection)
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
                self?.invalidateConnection(connection)
                gate.resolve((false, "xpc_error", false))
            }) as? HelperToolProtocol else {
                invalidateConnection(connection)
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
        guard let requestConnection,
              connectionLifecycle.acceptReply(from: requestConnection, didReply: didReply) else {
            return false
        }
        guard error == nil, success else {
            invalidateConnection(requestConnection)
            return false
        }
        markRoundTripSuccessful(requestConnection)
        return true
    }

    private func connectionForRequest() throws -> NSXPCConnection {
        connectionCreationLock.lock()
        defer { connectionCreationLock.unlock() }
        if let connection = connectionLifecycle.current() {
            return connection
        }

        let connection = NSXPCConnection(
            machServiceName: helperMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperToolProtocol.self)
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.invalidateConnection(connection)
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.invalidateConnection(connection)
        }

        do {
            let requirement = try helperCodeSigningRequirement()
            connection.setCodeSigningRequirement(requirement)
        } catch {
            connection.invalidate()
            throw error
        }
        connectionLifecycle.install(connection)
        connection.activate()
        return connection
    }

    private func invalidateConnection(_ failedConnection: NSXPCConnection) {
        connectionLifecycle.invalidate(failedConnection)
    }

    private func markRoundTripSuccessful(_ successfulConnection: NSXPCConnection) {
        connectionLifecycle.markRoundTripSuccessful(successfulConnection)
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
