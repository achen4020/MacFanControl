import Foundation

public final class ExclusiveOperationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isRunning = false

    public init() {}

    public func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    public func end() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }
}
