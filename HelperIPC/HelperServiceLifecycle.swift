public enum HelperServiceAction: Equatable, Sendable {
    case register
    case openApprovalSettings
    case retryConnection

    public var title: String {
        switch self {
        case .register:
            return "安装风扇控制服务"
        case .openApprovalSettings:
            return "打开系统设置"
        case .retryConnection:
            return "重试连接"
        }
    }
}

public struct HelperServicePresentation: Equatable, Sendable {
    public let message: String
    public let action: HelperServiceAction?
    public let isSuccess: Bool

    public init(registrationState: HelperRegistrationState, isConnectionAvailable: Bool) {
        switch (registrationState, isConnectionAvailable) {
        case (.enabled, true):
            message = "风扇控制服务已启用"
            action = nil
            isSuccess = true
        case (.enabled, false):
            message = "服务已启用，但当前无法连接"
            action = .retryConnection
            isSuccess = false
        case (.notRegistered, _):
            message = registrationState.message
            action = .register
            isSuccess = false
        case (.requiresApproval, _):
            message = registrationState.message
            action = .openApprovalSettings
            isSuccess = false
        case (.notFound, _):
            message = registrationState.message
            action = nil
            isSuccess = false
        }
    }
}

public actor HelperLifecycleGate {
    private var isBusy = false

    public init() {}

    public func tryBegin() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    public func end() {
        isBusy = false
    }
}

public enum HelperUninstallResult: Equatable, Sendable {
    case success
    case cleanupFailed
    case unregisterFailed
}

public enum HelperLegacyMigrationResult: Equatable, Sendable {
    case notConnected
    case cleaned
    case cleanupFailed
}

public enum HelperLegacyMigrationCoordinator {
    public static func migrateIfConnected(
        _ isConnected: Bool,
        cleanup: () async -> Bool
    ) async -> HelperLegacyMigrationResult {
        guard isConnected else { return .notConnected }
        return await cleanup() ? .cleaned : .cleanupFailed
    }
}

public enum HelperUninstallCoordinator {
    public static func uninstall(
        cleanup: () async -> Bool,
        unregister: () async throws -> Void
    ) async -> HelperUninstallResult {
        guard await cleanup() else {
            return .cleanupFailed
        }
        do {
            try await unregister()
            return .success
        } catch {
            return .unregisterFailed
        }
    }
}
