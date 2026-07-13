import Foundation

/// Bridges a single XPC reply callback into async code without double-resuming.
public final class ReplyGate<Value: Sendable>: @unchecked Sendable {
    private enum State {
        case pending([CheckedContinuation<Value, Never>])
        case resolved(Value)
    }

    private let lock = NSLock()
    private var state: State = .pending([])

    public init() {}

    public func resolve(_ value: Value) {
        let continuations: [CheckedContinuation<Value, Never>]
        lock.lock()
        switch state {
        case .resolved:
            lock.unlock()
            return
        case .pending(let waiting):
            state = .resolved(value)
            continuations = waiting
            lock.unlock()
        }
        continuations.forEach { $0.resume(returning: value) }
    }

    public func wait(timeout: Duration, fallback: Value) async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            switch state {
            case .resolved(let value):
                lock.unlock()
                continuation.resume(returning: value)
            case .pending(var waiting):
                waiting.append(continuation)
                state = .pending(waiting)
                lock.unlock()

                Task { [self] in
                    try? await Task.sleep(for: timeout)
                    resolve(fallback)
                }
            }
        }
    }
}
