import Foundation

public enum CodeSigningRequirementError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidTeamID
}

public struct CodeSigningRequirement: Equatable, Sendable {
    public let text: String

    public init(identifier: String, teamID: String) throws {
        guard identifier.matchesEntirePattern("[A-Za-z0-9.-]+") else {
            throw CodeSigningRequirementError.invalidIdentifier
        }
        guard teamID.matchesEntirePattern("[A-Z0-9]{10}") else {
            throw CodeSigningRequirementError.invalidTeamID
        }

        text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

private extension String {
    func matchesEntirePattern(_ pattern: String) -> Bool {
        range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
    }
}
