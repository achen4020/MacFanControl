import AppKit

public enum ScreenshotEditorWindowLayout {
    public static let defaultContentSize = NSSize(width: 960, height: 680)
    public static let minimumWindowSize = NSSize(width: 720, height: 520)

    public static func apply(to window: NSWindow) {
        window.minSize = minimumWindowSize
        window.setContentSize(defaultContentSize)
    }
}
