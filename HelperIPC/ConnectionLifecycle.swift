import Foundation

/// Owns the currently active connection and guarantees one-time invalidation.
public final class ConnectionLifecycle<Connection: AnyObject>: @unchecked Sendable {
    private let lock = NSLock()
    private let invalidation: (Connection) -> Void
    private var connection: Connection?
    private var available = false

    public init(invalidate: @escaping (Connection) -> Void) {
        self.invalidation = invalidate
    }

    public var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return available
    }

    public func current() -> Connection? {
        lock.lock()
        defer { lock.unlock() }
        return connection
    }

    public func install(_ connection: Connection) {
        lock.lock()
        self.connection = connection
        available = false
        lock.unlock()
    }

    public func markRoundTripSuccessful(_ connection: Connection) {
        lock.lock()
        if self.connection === connection {
            available = true
        }
        lock.unlock()
    }

    public func acceptReply(from connection: Connection, didReply: Bool) -> Bool {
        guard didReply else {
            invalidate(connection)
            return false
        }

        lock.lock()
        defer { lock.unlock() }
        return self.connection === connection
    }

    public func invalidate(_ connection: Connection) {
        let shouldInvalidate: Bool
        lock.lock()
        if self.connection === connection {
            self.connection = nil
            available = false
            shouldInvalidate = true
        } else {
            shouldInvalidate = false
        }
        lock.unlock()

        if shouldInvalidate {
            invalidation(connection)
        }
    }
}
