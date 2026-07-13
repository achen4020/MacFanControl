public enum HelperConnectionRetryCoordinator {
    @discardableResult
    public static func retry(
        for state: HelperRegistrationState,
        disconnect: @escaping @Sendable () async -> Void,
        request: @escaping @Sendable () async -> Void
    ) async -> Bool {
        guard state == .notFound || state == .enabled else {
            return false
        }

        await disconnect()
        await request()
        return true
    }
}
