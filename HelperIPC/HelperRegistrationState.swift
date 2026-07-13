public enum HelperRegistrationState: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    public var actionTitle: String? {
        switch self {
        case .notRegistered:
            return "安装风扇控制服务"
        case .requiresApproval:
            return "打开系统设置"
        case .notFound:
            return nil
        case .enabled:
            return nil
        }
    }

    public var message: String {
        switch self {
        case .notRegistered:
            return "需要安装风扇控制服务"
        case .requiresApproval:
            return "需要在系统设置中批准风扇控制服务"
        case .notFound:
            return "应用不完整，请重新下载或安装"
        case .enabled:
            return "风扇控制服务已启用"
        }
    }
}
