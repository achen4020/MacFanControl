import Foundation

public struct LegacyCommandResult: Equatable, Sendable {
    public let terminationStatus: Int32
    public let output: String

    public init(terminationStatus: Int32, output: String) {
        self.terminationStatus = terminationStatus
        self.output = output
    }
}

public protocol LegacyCommandExecuting: AnyObject {
    func execute(executable: String, arguments: [String]) throws -> LegacyCommandResult
}

public protocol LegacyFileRemoving: AnyObject {
    func removeItemIfPresent(atPath path: String) throws
}

public protocol LegacyHelperRemoving: AnyObject {
    func remove() -> HelperOperationResult
}

public final class LegacyHelperRemover: LegacyHelperRemoving {
    private static let legacyPlist = "/Library/LaunchDaemons/com.macfancontrol.smchelper.plist"
    private static let legacyPaths = [
        legacyPlist,
        "/Library/PrivilegedHelperTools/com.macfancontrol.smchelper",
        "/var/run/com.macfancontrol.smchelper.sock"
    ]

    private let executor: LegacyCommandExecuting
    private let fileRemover: LegacyFileRemoving

    public init(executor: LegacyCommandExecuting, fileRemover: LegacyFileRemoving) {
        self.executor = executor
        self.fileRemover = fileRemover
    }

    public convenience init() {
        self.init(executor: ProcessLegacyCommandExecutor(), fileRemover: FileManagerLegacyFileRemover())
    }

    public func remove() -> HelperOperationResult {
        let commandResult: LegacyCommandResult
        do {
            commandResult = try executor.execute(
                executable: "/bin/launchctl",
                arguments: ["bootout", "system", Self.legacyPlist]
            )
        } catch {
            return HelperOperationResult(success: false, error: "legacy_bootout_failed")
        }

        guard commandResult.terminationStatus == 0 || isServiceNotLoaded(commandResult.output) else {
            return HelperOperationResult(success: false, error: "legacy_bootout_failed")
        }

        var removalFailed = false
        for path in Self.legacyPaths {
            do {
                try fileRemover.removeItemIfPresent(atPath: path)
            } catch {
                removalFailed = true
            }
        }

        return removalFailed
            ? HelperOperationResult(success: false, error: "legacy_file_removal_failed")
            : HelperOperationResult(success: true, error: nil)
    }

    private func isServiceNotLoaded(_ output: String) -> Bool {
        let normalized = output.lowercased()
        return normalized.contains("could not find service")
            || normalized.contains("service not found")
            || normalized.contains("no such process")
    }
}

public final class ProcessLegacyCommandExecutor: LegacyCommandExecuting {
    public init() {}

    public func execute(executable: String, arguments: [String]) throws -> LegacyCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return LegacyCommandResult(
            terminationStatus: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }
}

public final class FileManagerLegacyFileRemover: LegacyFileRemoving {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func removeItemIfPresent(atPath path: String) throws {
        guard fileManager.fileExists(atPath: path) else { return }
        try fileManager.removeItem(atPath: path)
    }
}
