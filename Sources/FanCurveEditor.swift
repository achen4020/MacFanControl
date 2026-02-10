// FanCurveEditor.swift - 风扇曲线编辑器视图

import SwiftUI
import MacFanControlCore
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
