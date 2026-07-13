import Dispatch
import Foundation
import HelperIPC
import MacFanControlHelperCore

private final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedService: HelperXPCService
    private let connectionsLock = NSLock()
    private var activeConnections: [ObjectIdentifier: NSXPCConnection] = [:]

    init(exportedService: HelperXPCService) {
        self.exportedService = exportedService
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let identifier = ObjectIdentifier(connection)
        connection.exportedInterface = NSXPCInterface(with: HelperToolProtocol.self)
        connection.exportedObject = exportedService
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.removeConnection(ObjectIdentifier(connection))
        }
        connectionsLock.lock()
        activeConnections[identifier] = connection
        connectionsLock.unlock()
        connection.activate()
        return true
    }

    private func removeConnection(_ identifier: ObjectIdentifier) {
        connectionsLock.lock()
        activeConnections.removeValue(forKey: identifier)
        connectionsLock.unlock()
    }
}

private func clientCodeSigningRequirement() throws -> String {
#if DEBUG && LOCAL_UNSIGNED_XPC
    NSLog("MacFanControlHelper is using explicit local unsigned XPC mode")
    return #"identifier "com.macfancontrol.app""#
#else
    let ownTeamID = try CurrentCodeSignature.teamIdentifier()
    return try CodeSigningRequirement(
        identifier: mainAppBundleIdentifier,
        teamID: ownTeamID
    ).text
#endif
}

private let hardware = SMCFanHardware()
private let helperService = HelperService(hardware: hardware)
private let exportedService = HelperXPCService(service: helperService)
private let listenerDelegate = HelperListenerDelegate(exportedService: exportedService)
private let listener = NSXPCListener(machServiceName: helperMachServiceName)

do {
    let requirement = try clientCodeSigningRequirement()
    listener.setConnectionCodeSigningRequirement(requirement)
} catch {
    NSLog("MacFanControlHelper configuration error: cannot establish signed XPC client requirement: \(error)")
    exit(78)
}

listener.delegate = listenerDelegate

signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let terminationQueue = DispatchQueue(label: "com.macfancontrol.helper.termination")
let terminationSignals = [SIGTERM, SIGINT].map { signalNumber in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: terminationQueue)
    source.setEventHandler {
        let result = helperService.resetAllFansToAuto()
        if !result.success {
            NSLog("MacFanControlHelper shutdown reset failed: \(result.error ?? "unknown_error")")
        }
        listener.invalidate()
        exit(result.success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    source.resume()
    return source
}

_ = terminationSignals
listener.activate()
dispatchMain()
