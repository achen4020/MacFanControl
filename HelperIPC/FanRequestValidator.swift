public enum ValidationResult: Equatable, Sendable {
    case valid
    case invalidFan
    case invalidRPM
}

public enum FanRequestValidator {
    public static func validate(
        index: Int,
        rpm: Int,
        ranges: [ClosedRange<Int>]
    ) -> ValidationResult {
        guard ranges.indices.contains(index) else {
            return .invalidFan
        }
        guard ranges[index].contains(rpm) else {
            return .invalidRPM
        }
        return .valid
    }
}
