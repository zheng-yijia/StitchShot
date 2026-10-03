import ImageEditorKit
import SwiftUI

/// 当前工具的参数面板。
struct EditorToolPanel: View {
    @ObservedObject var vm: EditorViewModel
    @Binding var mosaicStyle: MosaicStyle
    @Binding var brushWidth: CGFloat
    @Binding var annotationKind: AnnotationKind
    @Binding var annotationColor: UIColor
    @Binding var annotationWidth: CGFloat
    var onApplyCrop: () -> Void
    var onClearCrop: () -> Void

    var body: some View {
        ScrollView {
            Group {
                switch vm.activeTool {
                case .crop:
                    CropPanel(onApply: onApplyCrop, onClear: onClearCrop)
                case .mosaic:
                    MosaicPanel(style: $mosaicStyle,
                                width: $brushWidth,
                                canUndo: !vm.model.mosaicStrokes.isEmpty,
                                onUndo: vm.removeLastMosaic)
                case .annotate:
                    AnnotatePanel(kind: $annotationKind,
                                  color: $annotationColor,
                                  width: $annotationWidth,
                                  canUndo: !vm.model.annotations.isEmpty,
                                  onUndo: vm.removeLastAnnotation)
                case .watermark:
                    WatermarkPanel(vm: vm)
                case .border:
                    BorderPanel(vm: vm)
                case .shell:
                    ShellPanel(vm: vm)
                case .statusBar:
                    StatusBarPanel(vm: vm)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 通用色板

struct ColorSwatchRow: View {
    @Binding var selected: UIColor

    private let colors: [UIColor] = [.white, .black, .red, .orange, .yellow, .green, .systemBlue, .purple]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { index in
                let color = colors[index]
                Circle()
                    .fill(Color(color))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .overlay(
                        Circle().stroke(Color.accentColor, lineWidth: 2)
                            .opacity(color.isEqual(selected) ? 1 : 0)
                    )
                    .onTapGesture { selected = color }
            }
        }
    }
}

// MARK: - 裁剪

private struct CropPanel: View {
    var onApply: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onApply) {
                Label("应用裁剪", systemImage: "checkmark")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            Button(action: onClear) {
                Label("去除裁剪", systemImage: "xmark")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 马赛克

private struct MosaicPanel: View {
    @Binding var style: MosaicStyle
    @Binding var width: CGFloat
    var canUndo: Bool
    var onUndo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("样式", selection: $style) {
                    ForEach(MosaicStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
            }
            HStack {
                Text("笔刷").font(.caption).foregroundColor(.secondary)
                Slider(value: $width, in: 0.02...0.12)
            }
        }
    }
}

// MARK: - 标注

private struct AnnotatePanel: View {
    @Binding var kind: AnnotationKind
    @Binding var color: UIColor
    @Binding var width: CGFloat
    var canUndo: Bool
    var onUndo: () -> Void

    private let icons: [AnnotationKind: String] = [
        .freehand: "pencil",
        .line: "line.diagonal",
        .arrow: "arrow.up.right",
        .rectangle: "rectangle",
        .ellipse: "circle"
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(AnnotationKind.allCases, id: \.self) { item in
                    Button(action: { kind = item }) {
                        Image(systemName: icons[item] ?? "pencil")
                            .font(.system(size: 17))
                            .frame(width: 34, height: 30)
                            .background(kind == item ? Color.accentColor.opacity(0.18) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
            }
            HStack {
                ColorSwatchRow(selected: $color)
                Spacer()
                Slider(value: $width, in: 0.005...0.03)
                    .frame(width: 110)
            }
        }
    }
}

// MARK: - 水印

private struct WatermarkPanel: View {
    @ObservedObject var vm: EditorViewModel

    private let positions: [WatermarkPosition] = [
        .topLeft, .topCenter, .topRight,
        .centerLeft, .center, .centerRight,
        .bottomLeft, .bottomCenter, .bottomRight
    ]

    var body: some View {
        VStack(spacing: 10) {
            Toggle("启用水印", isOn: Binding(
                get: { vm.model.watermark != nil },
                set: { vm.setWatermark($0 ? WatermarkConfig() : nil) }
            ))
            .font(.subheadline)
            if let config = vm.model.watermark {
                TextField("水印文字", text: Binding(
                    get: { config.text },
                    set: { text in vm.updateWatermark { $0.text = text } }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                HStack {
                    positionGrid(current: config.position)
                    Spacer()
                    ColorSwatchRow(selected: Binding(
                        get: { config.color },
                        set: { color in vm.updateWatermark { $0.color = color } }
                    ))
                }
                HStack {
                    Text("大小").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { config.sizeFraction },
                        set: { value in vm.updateWatermark { $0.sizeFraction = value } }
                    ), in: 0.02...0.15)
                    Text("透明").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { config.opacity },
                        set: { value in vm.updateWatermark { $0.opacity = value } }
                    ), in: 0.2...1)
                }
            }
        }
    }

    private func positionGrid(current: WatermarkPosition) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<3) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3) { column in
                        let position = positions[row * 3 + column]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(position == current ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 14, height: 14)
                            .onTapGesture { vm.updateWatermark { $0.position = position } }
                    }
                }
            }
        }
    }
}

// MARK: - 边框

private struct BorderPanel: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        VStack(spacing: 10) {
            Toggle("启用边框", isOn: Binding(
                get: { vm.model.border != nil },
                set: { vm.setBorder($0 ? BorderConfig() : nil) }
            ))
            .font(.subheadline)
            if let config = vm.model.border {
                HStack {
                    Text("宽度").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { config.thicknessFraction },
                        set: { value in vm.updateBorder { $0.thicknessFraction = value } }
                    ), in: 0.01...0.15)
                }
                HStack {
                    Text("颜色").font(.caption).foregroundColor(.secondary)
                    ColorSwatchRow(selected: Binding(
                        get: { config.color },
                        set: { color in vm.updateBorder { $0.color = color } }
                    ))
                }
            }
        }
    }
}

// MARK: - 带壳

private struct ShellPanel: View {
    @ObservedObject var vm: EditorViewModel
    @ObservedObject private var pro = ProUpgradeManager.shared
    @State private var showPaywall = false

    private let backgrounds: [UIColor] = [.darkGray, .black, .white, .systemBlue, .systemPink]

    var body: some View {
        VStack(spacing: 10) {
            Toggle("启用带壳", isOn: Binding(
                get: { vm.model.shell != nil },
                set: { enable in
                    if enable, !pro.isPro {
                        showPaywall = true
                    } else {
                        vm.setShell(enable ? ShellConfig() : nil)
                    }
                }
            ))
            .font(.subheadline)
            .sheet(isPresented: $showPaywall) { PaywallView() }
            if let config = vm.model.shell {
                Picker("设备", selection: Binding(
                    get: { config.device },
                    set: { device in vm.updateShell { $0.device = device } }
                )) {
                    ForEach(DeviceKind.allCases, id: \.self) { device in
                        Text(device.displayName).tag(device)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("背景").font(.caption).foregroundColor(.secondary)
                    ForEach(backgrounds.indices, id: \.self) { index in
                        let color = backgrounds[index]
                        Circle()
                            .fill(Color(color))
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                            .overlay(
                                Circle().stroke(Color.accentColor, lineWidth: 2)
                                    .opacity(color.isEqual(config.background) ? 1 : 0)
                            )
                            .onTapGesture { vm.updateShell { $0.background = color } }
                    }
                }
            }
        }
    }
}

// MARK: - 状态栏

private struct StatusBarPanel: View {
    @ObservedObject var vm: EditorViewModel

    var body: some View {
        VStack(spacing: 10) {
            Toggle("清理状态栏", isOn: Binding(
                get: { vm.model.statusBarClean != nil },
                set: { vm.setStatusBarClean($0 ? StatusBarCleanConfig() : nil) }
            ))
            .font(.subheadline)
            if let config = vm.model.statusBarClean {
                Picker("样式", selection: Binding(
                    get: { config.style },
                    set: { style in vm.updateStatusBarClean { $0.style = style } }
                )) {
                    ForEach(StatusBarCleanStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("高度").font(.caption).foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { config.heightFraction },
                        set: { value in vm.updateStatusBarClean { $0.heightFraction = value } }
                    ), in: 0.03...0.09)
                }
            }
        }
    }
}
