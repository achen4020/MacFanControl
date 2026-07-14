public enum FanControlTransport: Equatable, Sendable {
    case helper
    case legacySMC

    public static func resolve(
        isAppleSilicon: Bool,
        helperAvailable: Bool
    ) -> FanControlTransport {
        if isAppleSilicon || helperAvailable {
            return .helper
        }
        return .legacySMC
    }
}
