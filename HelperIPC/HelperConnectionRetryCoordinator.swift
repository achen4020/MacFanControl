public enum HelperConnectionRetryCoordinator {
    @discardableResult
    public static func retry(
        for state: HelperRegistrationState,
        disconnect: () async -> Void,
        request: () async -> Bool
    ) async -> Bool {
        guard state == .notFound || state == .enabled else {
            return false
        }

        await disconnect()
        return await request()
    }
}
