import Carbon.HIToolbox
import Combine
import ScreenshotKit

@MainActor
final class GlobalHotKeyManager: ObservableObject {
    static let shared = GlobalHotKeyManager()

    @Published private(set) var currentHotKey: ScreenshotHotKey
    @Published private(set) var lastError: String?

    var onTrigger: (() -> Void)?

    private let store: ScreenshotHotKeyStore
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1

    init(store: ScreenshotHotKeyStore = ScreenshotHotKeyStore()) {
        self.store = store
        currentHotKey = store.load()
    }

    var displayText: String {
        currentHotKey.displayText
    }

    func start() throws {
        try installHandlerIfNeeded()
        try register(currentHotKey, persist: false)
    }

    func replace(with hotKey: ScreenshotHotKey) throws {
        try installHandlerIfNeeded()
        try register(hotKey, persist: true)
    }

    func restoreDefault() throws {
        try replace(with: .default)
    }

    func stop() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func register(_ hotKey: ScreenshotHotKey, persist: Bool) throws {
        guard !hotKey.modifiers.isEmpty else {
            throw ScreenshotHotKeyError.missingModifier
        }

        let identifier = nextIdentifier
        nextIdentifier &+= 1
        var candidate: EventHotKeyRef?
        let eventID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            carbonModifiers(hotKey.modifiers),
            eventID,
            GetApplicationEventTarget(),
            0,
            &candidate
        )
        guard status == noErr, let candidate else {
            lastError = ScreenshotHotKeyError.registrationFailed.localizedDescription
            throw ScreenshotHotKeyError.registrationFailed
        }

        do {
            if persist {
                try store.save(hotKey)
            }
        } catch {
            UnregisterEventHotKey(candidate)
            throw error
        }

        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
        hotKeyReference = candidate
        currentHotKey = hotKey
        lastError = nil
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            throw ScreenshotHotKeyError.registrationFailed
        }
    }

    private func carbonModifiers(_ modifiers: ScreenshotModifier) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    private static let signature = OSType(0x4D_46_43_53) // MFCS
}
