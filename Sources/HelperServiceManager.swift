import HelperIPC
import ServiceManagement

@MainActor
final class HelperServiceManager {
    static let shared = HelperServiceManager()

    private let service: SMAppService

    init(service: SMAppService = SMAppService.daemon(plistName: "com.macfancontrol.helper.plist")) {
        self.service = service
    }

    var state: HelperRegistrationState {
        switch service.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() async throws {
        try await service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
