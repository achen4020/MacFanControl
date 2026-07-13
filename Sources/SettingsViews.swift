// SettingsViews.swift - 设置、关于页面及系统管理器

import SwiftUI
import UserNotifications
import ServiceManagement
import ScreenshotKit
// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("通用", systemImage: "gear")
                }

            ProfileSettingsView()
                .environmentObject(fanController)
                .tabItem {
                    Label("配置", systemImage: "slider.horizontal.3")
                }

            ScreenshotSettingsView()
                .tabItem {
                    Label("截图", systemImage: "camera.viewfinder")
                }

            AboutView()
                .environmentObject(fanController)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 380)
    }
}

struct ScreenshotSettingsView: View {
    @ObservedObject private var hotKeyManager = GlobalHotKeyManager.shared
    @State private var hotKey = GlobalHotKeyManager.shared.currentHotKey
    @State private var errorMessage: String?
    @State private var hasPermission = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Text("快捷键").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("区域截图")
                        Spacer()
                        ScreenshotHotKeyRecorder(hotKey: $hotKey) { value in
                            replaceHotKey(with: value)
                        }
                        .frame(width: 150, height: 30)
                    }
                    Text("点击快捷键框后录入新组合，必须包含至少一个修饰键；按 Esc 取消。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("恢复默认快捷键") {
                        do {
                            try hotKeyManager.restoreDefault()
                            hotKey = hotKeyManager.currentHotKey
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            GroupBox(label: Text("屏幕录制权限").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(hasPermission ? .green : .orange)
                        Text(hasPermission ? "已授权，可使用区域截图" : "未授权，区域截图无法读取屏幕画面")
                    }
                    HStack {
                        if !hasPermission {
                            Button("请求权限") {
                                _ = CGRequestScreenCaptureAccess()
                                refreshPermission()
                            }
                        }
                        Button("打开系统设置") {
                            openScreenCaptureSettings()
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Spacer()
        }
        .padding()
        .onAppear {
            hotKey = hotKeyManager.currentHotKey
            refreshPermission()
        }
    }

    private func replaceHotKey(with value: ScreenshotHotKey) {
        do {
            try hotKeyManager.replace(with: value)
            hotKey = hotKeyManager.currentHotKey
            errorMessage = nil
        } catch {
            hotKey = hotKeyManager.currentHotKey
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPermission() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    private func openScreenCaptureSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showTemperatureInMenuBar") var showTemperature = true
    @AppStorage("enableHighTempNotification") var enableHighTempNotification = true
    @AppStorage("highTempThreshold") var highTempThreshold = 90.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 启动设置
            GroupBox(label: Text("启动").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("登录时启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            LaunchAtLoginManager.shared.setLaunchAtLogin(newValue)
                        }
                    Toggle("在菜单栏显示温度", isOn: $showTemperature)
                }
                .padding(.vertical, 8)
            }

            // 通知设置
            GroupBox(label: Text("通知").font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("高温通知", isOn: $enableHighTempNotification)
                        .onChange(of: enableHighTempNotification) { newValue in
                            if newValue {
                                NotificationManager.shared.requestPermission()
                            }
                        }

                    if enableHighTempNotification {
                        HStack {
                            Text("温度阈值")
                            Spacer()
                            Picker("", selection: $highTempThreshold) {
                                Text("80°C").tag(80.0)
                                Text("85°C").tag(85.0)
                                Text("90°C").tag(90.0)
                                Text("95°C").tag(95.0)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 100)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // 同步开机启动状态
            launchAtLogin = LaunchAtLoginManager.shared.isLaunchAtLoginEnabled
        }
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        VStack(spacing: 16) {
            Text("温度-转速曲线配置")
                .font(.headline)

            List(fanController.profiles) { profile in
                HStack {
                    Image(systemName: profileIcon(for: profile.name))
                        .foregroundColor(profile.isActive ? .accentColor : .secondary)
                    Text(profile.name)
                        .fontWeight(profile.isActive ? .medium : .regular)
                    Spacer()
                    Text("\(profile.curve.count) 个控制点")
                        .foregroundColor(.secondary)
                    if profile.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }

            Button("打开曲线编辑器") {
                FanCurveWindowController.shared.showWindow()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func profileIcon(for name: String) -> String {
        switch name {
        case "静音": return "moon.fill"
        case "平衡": return "scalemass.fill"
        case "性能": return "bolt.fill"
        case "自定义": return "slider.horizontal.3"
        default: return "fan.fill"
        }
    }
}

struct AboutView: View {
    @EnvironmentObject var fanController: FanController
    @State private var isUninstallingHelper = false
    @State private var showUninstallAlert = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fan.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Mac 风扇控制")
                .font(.title2)
                .fontWeight(.bold)

            Text("版本 1.1.0")
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            // 系统信息
            VStack(spacing: 4) {
                Text(fanController.platformInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if fanController.isAppleSilicon {
                    if fanController.helperServicePresentation.isSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(fanController.helperServicePresentation.message)
                                .font(.caption)
                        }

                        Button("卸载服务") {
                            showUninstallAlert = true
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .disabled(isUninstallingHelper || fanController.isInstallingHelper)
                    } else {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(fanController.helperServicePresentation.message)
                                .font(.caption)
                        }

                        if let action = fanController.helperServicePresentation.action {
                            Button(action.title) {
                                fanController.performHelperRegistrationAction()
                            }
                            .font(.caption)
                            .disabled(fanController.isInstallingHelper)
                        }
                    }
                }
            }

            Text("一个简洁的 Mac 风扇监控和控制工具")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
        .alert("确认卸载", isPresented: $showUninstallAlert) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                uninstallHelper()
            }
        } message: {
            Text("确定要卸载风扇控制服务吗？卸载后将无法手动控制风扇转速。")
        }
    }

    private func uninstallHelper() {
        isUninstallingHelper = true
        Task { @MainActor in
            await fanController.uninstallHelper()
            isUninstallingHelper = false
        }
    }
}

// MARK: - Launch At Login Manager (开机自启动管理)

class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            // macOS 12 及更早版本的后备方案
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        }
    }
}

// MARK: - Notification Manager (通知管理)

class NotificationManager {
    static let shared = NotificationManager()

    private var lastNotificationTime: Date?
    private let notificationCooldown: TimeInterval = 300 // 5分钟冷却时间

    private init() {
        requestPermission()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func sendHighTemperatureNotification(temperature: Double) {
        // 检查冷却时间
        if let lastTime = lastNotificationTime,
           Date().timeIntervalSince(lastTime) < notificationCooldown {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "温度警告"
        content.body = String(format: "CPU 温度已达到 %.1f°C，请注意散热！", temperature)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "highTemp-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }

        lastNotificationTime = Date()
    }

    func sendFanSpeedNotification(speed: Int, mode: String) {
        let content = UNMutableNotificationContent()
        content.title = "风扇模式已切换"
        content.body = "当前模式: \(mode)，转速: \(speed) RPM"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "fanMode-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
