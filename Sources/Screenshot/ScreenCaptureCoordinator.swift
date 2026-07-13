import AppKit
import Combine
import ScreenshotKit

@MainActor
final class ScreenCaptureCoordinator: ObservableObject {
    static let shared = ScreenCaptureCoordinator()

    @Published private(set) var lastError: String?

    var onImageCaptured: ((CGImage) -> Void)?

    private let provider: ScreenCaptureProviding
    private let overlay: SelectionOverlayController
    private var session = ScreenCaptureSessionState()

    init(
        provider: ScreenCaptureProviding = CoreGraphicsScreenCaptureProvider(),
        overlay: SelectionOverlayController? = nil
    ) {
        self.provider = provider
        self.overlay = overlay ?? SelectionOverlayController()
    }

    func startCapture() {
        guard session.begin() else { return }
        lastError = nil

        guard provider.hasPermission() else {
            session.finish()
            showPermissionPrompt()
            return
        }

        do {
            let capture = try provider.captureDisplay(containing: NSEvent.mouseLocation)
            NSApp.activate(ignoringOtherApps: true)
            overlay.present(capture: capture) { [weak self] selection in
                self?.complete(capture: capture, selection: selection)
            }
        } catch {
            session.finish()
            report(error)
        }
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    private func complete(
        capture: CapturedDisplay,
        selection: ScreenshotSelection?
    ) {
        defer { session.finish() }
        guard let selection else { return }

        let pixelRect = capture.geometry.pixelRect(forLocalSelection: selection.rect)
        guard !pixelRect.isNull,
              !pixelRect.isEmpty,
              let croppedImage = capture.image.cropping(to: pixelRect) else {
            report(ScreenCaptureError.captureFailed)
            return
        }
        onImageCaptured?(croppedImage)
    }

    private func showPermissionPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "区域截图需要读取屏幕画面。授权后请重新启动 MacFanControl。"
        alert.addButton(withTitle: "请求权限")
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            _ = provider.requestPermission()
        case .alertSecondButtonReturn:
            openScreenCaptureSettings()
        default:
            break
        }
    }

    private func openScreenCaptureSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
