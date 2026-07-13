import Foundation
import Security

public enum CurrentCodeSignatureError: Error, Equatable, Sendable {
    case copySelfFailed(OSStatus)
    case copyStaticCodeFailed(OSStatus)
    case copySigningInformationFailed(OSStatus)
    case missingSigningInformation
    case missingTeamIdentifier
    case invalidTeamIdentifier
}

public enum CurrentCodeSignature {
    public static func teamIdentifier() throws -> String {
        var currentCode: SecCode?
        let copySelfStatus = SecCodeCopySelf([], &currentCode)
        guard copySelfStatus == errSecSuccess, let currentCode else {
            throw CurrentCodeSignatureError.copySelfFailed(copySelfStatus)
        }

        var staticCode: SecStaticCode?
        let copyStaticCodeStatus = SecCodeCopyStaticCode(currentCode, [], &staticCode)
        guard copyStaticCodeStatus == errSecSuccess, let staticCode else {
            throw CurrentCodeSignatureError.copyStaticCodeFailed(copyStaticCodeStatus)
        }

        var signingInformation: CFDictionary?
        let signingStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard signingStatus == errSecSuccess else {
            throw CurrentCodeSignatureError.copySigningInformationFailed(signingStatus)
        }
        guard let signingInformation = signingInformation as? [String: Any] else {
            throw CurrentCodeSignatureError.missingSigningInformation
        }

        return try teamIdentifier(from: signingInformation)
    }

    public static func teamIdentifier(from signingInformation: [String: Any]) throws -> String {
        let key = kSecCodeInfoTeamIdentifier as String
        guard let rawTeamIdentifier = signingInformation[key] else {
            throw CurrentCodeSignatureError.missingTeamIdentifier
        }
        guard let teamIdentifier = rawTeamIdentifier as? String else {
            throw CurrentCodeSignatureError.invalidTeamIdentifier
        }
        do {
            _ = try CodeSigningRequirement(identifier: mainAppBundleIdentifier, teamID: teamIdentifier)
        } catch {
            throw CurrentCodeSignatureError.invalidTeamIdentifier
        }
        return teamIdentifier
    }
}
