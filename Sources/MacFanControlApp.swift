// MacFanControlApp.swift - Main SwiftUI App with MenuBar

import SwiftUI

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

// MARK: - Menu Bar Label (状态栏图标)

struct MenuBarLabel: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "fan.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(iconColor)

            if fanController.isMonitoring {
                Text(temperatureText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(tempColor)
            }
        }
    }

    private var temperatureText: String {
        String(format: "%.0f°", fanController.cpuTemperature)
    }

    // 图标颜色根据温度变化
    private var iconColor: Color {
        let temp = fanController.cpuTemperature
        if temp >= 90 { return .red }
        if temp >= 75 { return .orange }
        if temp >= 60 { return .yellow }
        return .primary
    }

    private var tempColor: Color {
        let temp = fanController.cpuTemperature
        if temp >= 90 { return .red }
        if temp >= 75 { return .orange }
        return .primary
    }
}

// MARK: - Menu Bar Content View (弹出窗口内容)

struct MenuBarContentView: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Mac 风扇控制")
                    .font(.headline)
                Spacer()

                // 显示风扇转速
                if let fan = fanController.fans.first {
                    Text("\(fan.currentSpeed) RPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if fanController.isMonitoring {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 4)

            // 温度过高警告
            if fanController.cpuTemperature >= 90 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("温度过高！请检查散热")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Helper 安装提示
            if fanController.needsHelperInstall {
                HelperInstallView()
                    .environmentObject(fanController)
            }

            Divider()

            // Temperature Section
            TemperatureSection()
                .environmentObject(fanController)

            Divider()

            // Fan Section
            FanSection()
                .environmentObject(fanController)

            Divider()

            // Profile Section
            ProfileSection()
                .environmentObject(fanController)

            Divider()

            // Error message if any
            if let error = fanController.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Bottom buttons
            HStack {
                // 曲线编辑按钮 - 打开独立窗口
                Button {
                    FanCurveWindowController.shared.showWindow()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.xyaxis.line")
                        Text("曲线编辑")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("退出") {
                    // 退出前恢复风扇为自动模式
                    fanController.resetAllFansToAuto()
                    // 稍微延迟确保命令执行完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            fanController.startMonitoring()
            // 自动检查并安装 helper
            if fanController.needsHelperInstall {
                fanController.checkAndInstallHelper()
            }
        }
    }
}

// MARK: - Helper Install View

struct HelperInstallView: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("需要安装风扇控制服务")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if fanController.isInstallingHelper {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在安装...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Button("安装服务 (需要管理员密码)") {
                    fanController.installHelper()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Temperature Section

struct TemperatureSection: View {
    @EnvironmentObject var fanController: FanController
    @State private var showMoreSensors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("温度")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(fanController.temperatureSource)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // CPU Temperature
            TemperatureRow(
                icon: "cpu",
                name: "CPU",
                temperature: fanController.cpuTemperature
            )

            // Max Temperature
            if fanController.maxTemperature > 0 && fanController.maxTemperature != fanController.cpuTemperature {
                TemperatureRow(
                    icon: "thermometer.high",
                    name: "最高",
                    temperature: fanController.maxTemperature
                )
            }

            // CPU Usage
            HStack {
                Image(systemName: "chart.bar.fill")
                    .frame(width: 20)
                Text("CPU 使用率")
                Spacer()
                Text(String(format: "%.1f%%", fanController.cpuUsage))
                    .monospacedDigit()
                    .foregroundColor(.blue)
            }

            // GPU Temperature (if available)
            if let gpuTemp = fanController.gpuTemperature {
                TemperatureRow(
                    icon: "gpu",
                    name: "GPU",
                    temperature: gpuTemp
                )
            }

            // Show all detected sensors
            if fanController.temperatures.count > 1 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMoreSensors.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: showMoreSensors ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .frame(width: 12)
                        Text("更多传感器 (\(fanController.temperatures.count))")
                            .font(.caption)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                if showMoreSensors {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fanController.temperatures.prefix(12)) { sensor in
                            HStack {
                                Text(sensor.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(sensor.formattedValue)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(sensorColor(sensor.value))
                            }
                        }
                        if fanController.temperatures.count > 12 {
                            Text("... 还有 \(fanController.temperatures.count - 12) 个传感器")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func sensorColor(_ temp: Double) -> Color {
        if temp >= 80 { return .red }
        if temp >= 60 { return .orange }
        if temp >= 45 { return .yellow }
        return .green
    }
}

struct TemperatureRow: View {
    let icon: String
    let name: String
    let temperature: Double

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(name)
            Spacer()
            Text(String(format: "%.1f°C", temperature))
                .foregroundColor(temperatureColor)
                .monospacedDigit()
                .fontWeight(.medium)
        }
    }

    private var temperatureColor: Color {
        if temperature >= 95 {
            return .red
        } else if temperature >= 80 {
            return .orange
        } else if temperature >= 60 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Fan Section

struct FanSection: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("风扇")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if fanController.isM4 {
                    Text("M4 限制")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if fanController.isAppleSilicon {
                    Text("系统自动管理")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            if fanController.fans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if fanController.isM4 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("M4 芯片限制")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text("Apple M4 芯片在固件层面锁定了风扇接口，第三方软件无法读取或控制风扇转速。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("风扇由 macOS 根据温度自动智能调节。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if fanController.isAppleSilicon {
                        Text("风扇由系统自动管理")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Apple Silicon Mac 的风扇由 macOS 智能控制")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("未检测到风扇")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(fanController.fans) { fan in
                    FanRow(fan: fan, fanIndex: fan.id)
                        .environmentObject(fanController)
                }
            }
        }
    }
}

struct FanRow: View {
    let fan: FanInfo
    let fanIndex: Int
    @EnvironmentObject var fanController: FanController
    @State private var speedPercentage: Double = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundColor(fanColor)
                    .frame(width: 20)

                Text("风扇 \(fanIndex + 1)")

                Spacer()

                Text("\(fan.currentSpeed) RPM")
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                // Mode indicator
                if fan.isManualMode {
                    Text("手动")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                } else {
                    Text("自动")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            // Speed slider
            HStack {
                Text("\(fan.minSpeed)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(
                    value: $speedPercentage,
                    in: 0...100,
                    step: 5
                ) { editing in
                    if !editing {
                        fanController.setFanSpeedPercentage(fanIndex: fanIndex, percentage: speedPercentage)
                    }
                }
                .disabled(!fanController.canControlFans)

                Text("\(fan.maxSpeed)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Progress bar showing current speed
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(speedColor)
                        .frame(width: geometry.size.width * CGFloat(fan.speedPercentage / 100), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .onAppear {
            speedPercentage = fan.speedPercentage
        }
        .onChange(of: fan.currentSpeed) { _ in
            if !fan.isManualMode {
                speedPercentage = fan.speedPercentage
            }
        }
    }

    private var fanColor: Color {
        let percentage = fan.speedPercentage
        if percentage < 30 {
            return .green
        } else if percentage < 60 {
            return .blue
        } else if percentage < 85 {
            return .orange
        } else {
            return .red
        }
    }

    private var speedColor: Color {
        let percentage = fan.speedPercentage
        if percentage < 30 {
            return .green
        } else if percentage < 60 {
            return .yellow
        } else if percentage < 85 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Profile Section

struct ProfileSection: View {
    @EnvironmentObject var fanController: FanController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自动控制配置")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { fanController.isAutoControlEnabled },
                    set: { enabled in
                        if enabled {
                            // Enable with balanced profile by default
                            if let balanced = fanController.profiles.first(where: { $0.name == "平衡" }) {
                                fanController.enableAutoControl(profile: balanced)
                            }
                        } else {
                            fanController.disableAutoControl()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            // Profile selection
            HStack(spacing: 6) {
                // 系统自动按钮
                Button {
                    fanController.resetAllFansToAuto()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3)
                        Text("自动")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(!fanController.isAutoControlEnabled && !hasManualFan ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(!fanController.isAutoControlEnabled && !hasManualFan ? Color.green : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // 预设配置按钮
                ForEach(fanController.profiles) { profile in
                    ProfileButton(profile: profile)
                        .environmentObject(fanController)
                }
            }
        }
    }

    private var hasManualFan: Bool {
        fanController.fans.contains { $0.isManualMode }
    }
}

struct ProfileButton: View {
    let profile: FanProfile
    @EnvironmentObject var fanController: FanController

    var body: some View {
        Button {
            fanController.enableAutoControl(profile: profile)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: profileIcon)
                    .font(.title3)
                Text(profile.name)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑曲线") {
                FanCurveWindowController.shared.showWindow()
            }
        }
    }

    private var isActive: Bool {
        fanController.activeProfile?.id == profile.id
    }

    private var profileIcon: String {
        switch profile.name {
        case "静音":
            return "moon.fill"
        case "平衡":
            return "scalemass.fill"
        case "性能":
            return "bolt.fill"
        default:
            return "slider.horizontal.3"
        }
    }
}

// MARK: - Fan Curve Editor View (风扇曲线编辑器)

struct FanCurveEditorView: View {
    @EnvironmentObject var fanController: FanController
    var onDismiss: (() -> Void)?

    @State private var curvePoints: [FanCurvePoint] = []
    @State private var selectedPointIndex: Int?
    @State private var syncFans = true

    // 坐标轴范围
    private let tempRange: ClosedRange<Double> = 20...100
    private let speedRange: ClosedRange<Double> = 0...100

    // 图表尺寸
    private let graphWidth: CGFloat = 320
    private let graphHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("风扇")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    Text("同步风扇")
                        .font(.caption)
                    Toggle("", isOn: $syncFans)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // 曲线图区域 (带坐标轴)
            HStack(alignment: .top, spacing: 4) {
                // Y轴标签 (转速 0-100%)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("100%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("75%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("50%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("25%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("0%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 32, height: graphHeight)

                // 图表区域
                VStack(spacing: 4) {
                    ZStack {
                        // 背景网格
                        CurveGridView(
                            width: graphWidth,
                            height: graphHeight,
                            tempRange: tempRange,
                            speedRange: speedRange
                        )

                        // 曲线
                        CurveLineView(
                            points: curvePoints,
                            width: graphWidth,
                            height: graphHeight,
                            tempRange: tempRange,
                            speedRange: speedRange
                        )

                        // 当前温度指示线
                        if fanController.cpuTemperature > 0 {
                            CurrentTempIndicator(
                                temperature: fanController.cpuTemperature,
                                width: graphWidth,
                                height: graphHeight,
                                tempRange: tempRange
                            )
                        }

                        // 控制点
                        ForEach(curvePoints.indices, id: \.self) { index in
                            CurvePointView(
                                point: $curvePoints[index],
                                isSelected: selectedPointIndex == index,
                                width: graphWidth,
                                height: graphHeight,
                                tempRange: tempRange,
                                speedRange: speedRange
                            )
                            .onTapGesture {
                                selectedPointIndex = index
                            }
                        }
                    }
                    .frame(width: graphWidth, height: graphHeight)
                    .clipped()

                    // X轴标签 (温度)
                    HStack {
                        Text("20°")
                        Spacer()
                        Text("40°")
                        Spacer()
                        Text("60°")
                        Spacer()
                        Text("80°")
                        Spacer()
                        Text("100°")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: graphWidth)
                }
            }
            .padding(.horizontal, 16)

            // 当前状态显示
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("当前温度:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f°C", fanController.cpuTemperature))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack {
                        Text("目标转速:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.0f%%", calculateTargetSpeed()))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal)

            // 选中点信息
            if let index = selectedPointIndex, index < curvePoints.count {
                HStack {
                    Text("控制点 \(index + 1):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f°C → %.0f%%",
                                curvePoints[index].temperature,
                                curvePoints[index].fanSpeedPercentage))
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    if curvePoints.count > 2 {
                        Button("删除") {
                            curvePoints.remove(at: index)
                            selectedPointIndex = nil
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // 底部按钮
            HStack {
                Button("重置") {
                    resetToDefault()
                }
                .buttonStyle(.bordered)

                Button("添加点") {
                    addPoint()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("完成") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .frame(width: 420, height: 360)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadCurrentProfile()
        }
    }

    private func loadCurrentProfile() {
        if let profile = fanController.activeProfile {
            curvePoints = profile.curve
        } else if let balanced = fanController.profiles.first(where: { $0.name == "平衡" }) {
            curvePoints = balanced.curve
        } else {
            resetToDefault()
        }
    }

    private func resetToDefault() {
        curvePoints = [
            FanCurvePoint(temperature: 20, fanSpeedPercentage: 0),
            FanCurvePoint(temperature: 50, fanSpeedPercentage: 75),
            FanCurvePoint(temperature: 100, fanSpeedPercentage: 100)
        ]
        selectedPointIndex = nil
    }

    private func addPoint() {
        // 在中间添加一个新点
        let sortedPoints = curvePoints.sorted { $0.temperature < $1.temperature }
        if sortedPoints.count >= 2 {
            let midIndex = sortedPoints.count / 2
            let lower = sortedPoints[midIndex - 1]
            let upper = sortedPoints[midIndex]
            let newTemp = (lower.temperature + upper.temperature) / 2
            let newSpeed = (lower.fanSpeedPercentage + upper.fanSpeedPercentage) / 2
            curvePoints.append(FanCurvePoint(temperature: newTemp, fanSpeedPercentage: newSpeed))
            selectedPointIndex = curvePoints.count - 1
        }
    }

    private func calculateTargetSpeed() -> Double {
        let temp = fanController.cpuTemperature
        let sortedPoints = curvePoints.sorted { $0.temperature < $1.temperature }

        guard !sortedPoints.isEmpty else { return 50 }

        if temp <= sortedPoints.first!.temperature {
            return sortedPoints.first!.fanSpeedPercentage
        }
        if temp >= sortedPoints.last!.temperature {
            return sortedPoints.last!.fanSpeedPercentage
        }

        for i in 0..<(sortedPoints.count - 1) {
            let lower = sortedPoints[i]
            let upper = sortedPoints[i + 1]
            if temp >= lower.temperature && temp <= upper.temperature {
                let ratio = (temp - lower.temperature) / (upper.temperature - lower.temperature)
                return lower.fanSpeedPercentage + ratio * (upper.fanSpeedPercentage - lower.fanSpeedPercentage)
            }
        }

        return 50
    }

    private func saveAndDismiss() {
        // 创建新的配置
        var newProfile = FanProfile(
            name: "自定义",
            curve: curvePoints.sorted { $0.temperature < $1.temperature }
        )
        newProfile.isActive = true

        // 更新或添加配置
        if let index = fanController.profiles.firstIndex(where: { $0.name == "自定义" }) {
            fanController.profiles[index] = newProfile
        } else {
            fanController.profiles.append(newProfile)
        }

        // 启用自动控制
        fanController.enableAutoControl(profile: newProfile)

        onDismiss?()
    }
}

// MARK: - Current Temperature Indicator (当前温度指示线)

struct CurrentTempIndicator: View {
    let temperature: Double
    let width: CGFloat
    let height: CGFloat
    let tempRange: ClosedRange<Double>

    var body: some View {
        let x = CGFloat((temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * width

        Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: height))
        }
        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
    }
}

// MARK: - Curve Grid View (网格背景)

struct CurveGridView: View {
    let width: CGFloat
    let height: CGFloat
    let tempRange: ClosedRange<Double>
    let speedRange: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            // 背景
            context.fill(
                Path(CGRect(origin: .zero, size: CGSize(width: width, height: height))),
                with: .color(Color.black.opacity(0.8))
            )

            // 网格线
            let gridColor = Color.gray.opacity(0.3)

            // 垂直线 (温度)
            for i in 0...4 {
                let x = CGFloat(i) * width / 4
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }

            // 水平线 (转速)
            for i in 0...4 {
                let y = CGFloat(i) * height / 4
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
            }
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Curve Line View (曲线)

struct CurveLineView: View {
    let points: [FanCurvePoint]
    let width: CGFloat
    let height: CGFloat
    let tempRange: ClosedRange<Double>
    let speedRange: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }

            let sortedPoints = points.sorted { $0.temperature < $1.temperature }

            var path = Path()
            for (index, point) in sortedPoints.enumerated() {
                let x = CGFloat((point.temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * width
                let y = height - CGFloat((point.fanSpeedPercentage - speedRange.lowerBound) / (speedRange.upperBound - speedRange.lowerBound)) * height

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Curve Point View (控制点)

struct CurvePointView: View {
    @Binding var point: FanCurvePoint
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let tempRange: ClosedRange<Double>
    let speedRange: ClosedRange<Double>

    @State private var dragOffset: CGSize = .zero

    private var xPosition: CGFloat {
        CGFloat((point.temperature - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)) * width
    }

    private var yPosition: CGFloat {
        height - CGFloat((point.fanSpeedPercentage - speedRange.lowerBound) / (speedRange.upperBound - speedRange.lowerBound)) * height
    }

    var body: some View {
        Circle()
            .fill(isSelected ? Color.white : Color.blue)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .position(x: xPosition, y: yPosition)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        // 计算新的温度和转速
                        let newX = max(0, min(width, value.location.x))
                        let newY = max(0, min(height, value.location.y))

                        let newTemp = tempRange.lowerBound + Double(newX / width) * (tempRange.upperBound - tempRange.lowerBound)
                        let newSpeed = speedRange.upperBound - Double(newY / height) * (speedRange.upperBound - speedRange.lowerBound)

                        // 限制范围并更新
                        point.temperature = max(tempRange.lowerBound, min(tempRange.upperBound, newTemp))
                        point.fanSpeedPercentage = max(speedRange.lowerBound, min(speedRange.upperBound, newSpeed))
                    }
            )
    }
}

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

            AboutView()
                .environmentObject(fanController)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showTemperatureInMenuBar") var showTemperature = true

    var body: some View {
        Form {
            Toggle("登录时启动", isOn: $launchAtLogin)
            Toggle("在菜单栏显示温度", isOn: $showTemperature)
        }
        .padding()
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

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fan.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Mac 风扇控制")
                .font(.title2)
                .fontWeight(.bold)

            Text("版本 1.0.0")
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            // 系统信息
            VStack(spacing: 4) {
                Text(fanController.platformInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if fanController.canControlFans {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("风扇控制服务已启用")
                            .font(.caption)
                    }
                } else {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("风扇控制服务未安装")
                            .font(.caption)
                    }
                }
            }

            Text("一个简洁的 Mac 风扇监控和控制工具")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }
}
