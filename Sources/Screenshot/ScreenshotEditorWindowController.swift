import AppKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorWindowController()

    private var documents: [NSWindow: ScreenshotEditorViewModel] = [:]

    func open(image: CGImage) {
        let viewModel = ScreenshotEditorViewModel(image: image)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let view = ScreenshotEditorView(
            viewModel: viewModel,
            onCancel: { [weak window] in window?.performClose(nil) },
            onCopy: {},
            onSave: {}
        )
        window.title = "截图编辑器"
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 520)
        window.center()
        documents[window] = viewModel
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard documents[sender]?.isDirty == true else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "放弃未保存的编辑？"
        alert.informativeText = "关闭窗口后，当前截图和标注将无法恢复。"
        alert.addButton(withTitle: "放弃")
        alert.addButton(withTitle: "继续编辑")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        documents.removeValue(forKey: window)
        window.contentViewController = nil
        window.delegate = nil
    }
}
