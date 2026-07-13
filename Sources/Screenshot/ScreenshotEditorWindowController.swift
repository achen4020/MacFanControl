import AppKit
import ScreenshotKit
import SwiftUI

@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = ScreenshotEditorWindowController()

    private var documents: [NSWindow: ScreenshotEditorViewModel] = [:]
    private var eventMonitors: [NSWindow: Any] = [:]

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
            onCopy: { [weak viewModel] in viewModel?.copyToPasteboard() },
            onSave: { [weak viewModel] in viewModel?.save() }
        )
        window.title = "截图编辑器"
        window.contentViewController = NSHostingController(rootView: view)
        window.delegate = self
        window.isReleasedWhenClosed = false
        ScreenshotEditorWindowLayout.apply(to: window)
        window.center()
        documents[window] = viewModel
        eventMonitors[window] = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak window] event in
            guard let window,
                  event.window === window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.keyCode == 9 else {
                return event
            }
            self?.openImageFromPasteboard(currentWindow: window)
            return nil
        }
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
        if let monitor = eventMonitors.removeValue(forKey: window) {
            NSEvent.removeMonitor(monitor)
        }
        window.contentViewController = nil
        window.delegate = nil
    }

    private func openImageFromPasteboard(currentWindow: NSWindow) {
        do {
            guard let image = NSImage(pasteboard: .general) else {
                throw ScreenshotClipboardError.noImage
            }
            var proposedRect = CGRect(origin: .zero, size: image.size)
            guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
                throw ScreenshotClipboardError.invalidImage
            }
            try ScreenshotClipboardPolicy().validate(width: cgImage.width, height: cgImage.height)

            if documents[currentWindow]?.isDirty == true {
                let alert = NSAlert()
                alert.messageText = "打开剪贴板图片？"
                alert.informativeText = "当前编辑会保留在原窗口，剪贴板图片将在新窗口打开。"
                alert.addButton(withTitle: "打开新窗口")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            open(image: cgImage)
        } catch {
            documents[currentWindow]?.errorMessage = error.localizedDescription
        }
    }
}
