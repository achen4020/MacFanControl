// MacFanControlApp.swift - Main SwiftUI App with MenuBar

import SwiftUI
import UserNotifications
import ServiceManagement

@main
struct MacFanControlApp: App {
    @StateObject private var fanController = FanController.shared

    var body: some Scene {
        // Menu Bar Extra (状态栏应用)
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(fanController)
        } label: {
            MenuBarLabel()
                .environmentObject(fanController)
        }
        .menuBarExtraStyle(.window)

        // Optional: Settings Window
        Settings {
            SettingsView()
                .environmentObject(fanController)
        }
    }
}

// MARK: - Fan Curve Window Controller (独立窗口控制器)

@MainActor
class FanCurveWindowController: NSObject {
    static let shared = FanCurveWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = FanCurveEditorView(onDismiss: { [weak self] in
            self?.closeWindow()
        })
        .environmentObject(FanController.shared)

        hostingController = NSHostingController(rootView: AnyView(contentView))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "风扇曲线编辑器"
        window?.contentViewController = hostingController
        window?.center()
        window?.isReleasedWhenClosed = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }
}

// MARK: - Settings Window Controller (设置窗口控制器)

@MainActor
class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    func showWindow() {
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = SettingsView()
            .environmentObject(FanController.shared)

        hostingController = NSHostingController(rootView: AnyView(contentView))

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window?.title = "设置"
        window?.contentViewController = hostingController
        window?.center()
        window?.isReleasedWhenClosed = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }
}
