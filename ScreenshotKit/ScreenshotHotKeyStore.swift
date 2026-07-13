import Foundation

public enum ScreenshotHotKeyError: LocalizedError, Equatable {
    case missingModifier
    case registrationFailed

    public var errorDescription: String? {
        switch self {
        case .missingModifier:
            return "快捷键必须包含至少一个修饰键"
        case .registrationFailed:
            return "快捷键已被系统或其他应用占用"
        }
    }
}

public final class ScreenshotHotKeyStore {
    private let defaults: UserDefaults
    private let storageKey = "screenshot.hotKey"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ScreenshotHotKey {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(ScreenshotHotKey.self, from: data) else {
            return .default
        }
        return value
    }

    public func save(_ hotKey: ScreenshotHotKey) throws {
        guard !hotKey.modifiers.isEmpty else {
            throw ScreenshotHotKeyError.missingModifier
        }
        defaults.set(try JSONEncoder().encode(hotKey), forKey: storageKey)
    }
}
