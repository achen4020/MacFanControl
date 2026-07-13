import AppKit
import ScreenshotKit
import SwiftUI

struct ScreenshotEditorView: View {
    @ObservedObject var viewModel: ScreenshotEditorViewModel
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                toolButton(.select, icon: "cursorarrow", title: "选择")
                toolButton(.crop, icon: "crop", title: "裁剪")
                toolButton(.rectangle, icon: "rectangle", title: "矩形")
                toolButton(.arrow, icon: "arrow.up.right", title: "箭头")
                toolButton(.pen, icon: "pencil.tip", title: "画笔")
                toolButton(.text, icon: "textformat", title: "文字")
                toolButton(.mosaic, icon: "square.grid.3x3", title: "马赛克")

                Divider().frame(height: 24)
                Button(action: viewModel.undo) { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!viewModel.canUndo)
                    .help("撤销")
                Button(action: viewModel.redo) { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!viewModel.canRedo)
                    .help("重做")

                Spacer()
                Button("取消", action: onCancel)
                Button("复制", action: onCopy)
                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .padding(10)

            Divider()

            ScreenshotCanvasView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                ColorPicker("颜色", selection: colorBinding, supportsOpacity: true)
                    .frame(width: 100)
                Text("线宽")
                Slider(value: lineWidthBinding, in: 1...20)
                    .frame(width: 140)
                Text("透明度")
                Slider(value: opacityBinding, in: 0.1...1)
                    .frame(width: 140)
                Spacer()
                Text("\(Int(viewModel.state.cropRect.width)) × \(Int(viewModel.state.cropRect.height))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .padding(10)
        }
        .alert("截图编辑失败", isPresented: errorPresented) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private func toolButton(_ tool: ScreenshotTool, icon: String, title: String) -> some View {
        Button {
            viewModel.tool = tool
        } label: {
            Label(title, systemImage: icon)
        }
        .tint(viewModel.tool == tool ? .accentColor : nil)
        .help(title)
    }

    private var colorBinding: Binding<Color> {
        Binding {
            let value = viewModel.style.color
            return Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
        } set: { color in
            let converted = NSColor(color).usingColorSpace(.deviceRGB) ?? .systemRed
            viewModel.style.color = ScreenshotColor(
                red: converted.redComponent,
                green: converted.greenComponent,
                blue: converted.blueComponent,
                alpha: converted.alphaComponent
            )
        }
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { viewModel.style.lineWidth },
            set: { viewModel.style.lineWidth = $0 }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { viewModel.style.opacity },
            set: { viewModel.style.opacity = $0 }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
