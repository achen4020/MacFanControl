// MenuBarViews.swift - 菜单栏相关视图组件

import SwiftUI
import MacFanControlCore
// MARK: - Menu Bar Label (状态栏图标)

struct MenuBarLabel: View {
    @EnvironmentObject var fanController: FanController
    @AppStorage("showTemperatureInMenuBar") var showTemperature = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "fan.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(iconColor)

            if fanController.isMonitoring && showTemperature {
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
                Text(error.localizedDescription)
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

                // 设置按钮
                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    Image(systemName: "gear")
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

            // Memory Usage
            HStack {
                Image(systemName: "memorychip")
                    .frame(width: 20)
                Text("内存")
                Spacer()
                Text("\(fanController.memoryUsed) / \(fanController.memoryTotal)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(memoryColor)
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

    private var memoryColor: Color {
        let usage = fanController.memoryUsage
        if usage >= 90 { return .red }
        if usage >= 75 { return .orange }
        if usage >= 50 { return .yellow }
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

                if fanController.isAppleSilicon && !fanController.canControlFans {
                    Text("需要安装服务")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if fanController.isAppleSilicon {
                    Text("已启用控制")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            if fanController.fans.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if fanController.isAppleSilicon && !fanController.canControlFans {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Apple Silicon Mac")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        Text("请安装风扇控制服务以启用风扇监控和控制功能。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("安装后可以查看风扇转速并手动调节。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if fanController.isAppleSilicon {
                        Text("正在获取风扇信息...")
                            .font(.caption)
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
                    fanController.disableAutoControl()
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
