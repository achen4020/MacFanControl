import Foundation

public struct CodeSigningRequirement: Equatable, Sendable {
    public let text: String

    public init?(identifier: String, teamID: String) {
        guard identifier.matchesEntirePattern("[A-Za-z0-9.-]+"),
              teamID.matchesEntirePattern("[A-Z0-9]{10}") else {
            return nil
        }

        text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

private extension String {
    func matchesEntirePattern(_ pattern: String) -> Bool {
        range(of: "^(?:\(pattern))$", options: .regularExpression) != nil
    }
}
