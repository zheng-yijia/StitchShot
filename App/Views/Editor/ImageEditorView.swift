import ImageEditorKit
import PhotoLibraryKit
import SwiftUI

/// 图片编辑器：预览区 + 手势覆盖层 + 工具面板 + 工具栏。
struct ImageEditorView: View {
    @StateObject private var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var cropDraft: CGRect?
    @State private var lastDisplayRect: CGRect?
    @State private var mosaicStyle: MosaicStyle = .pixelate
    @State private var brushWidth: CGFloat = 0.06
    @State private var annotationKind: AnnotationKind = .arrow
    @State private var annotationColor: UIColor = .red
    @State private var annotationWidth: CGFloat = 0.012
    @State private var didSave = false
    @State private var showSaveResult = false

    private let service = PhotoLibraryService()

    init(original: UIImage, presetTool: EditorTool? = nil) {
        _vm = StateObject(wrappedValue: EditorViewModel(original: original, presetTool: presetTool))
    }

    var body: some View {
        VStack(spacing: 0) {
            previewArea
            Divider()
            EditorToolPanel(
                vm: vm,
                mosaicStyle: $mosaicStyle,
                brushWidth: $brushWidth,
                annotationKind: $annotationKind,
                annotationColor: $annotationColor,
                annotationWidth: $annotationWidth,
                onApplyCrop: applyCrop,
                onClearCrop: {
                    cropDraft = nil
                    vm.commitCrop(nil)
                }
            )
            .frame(height: 150)
            .background(Color(uiColor: .secondarySystemBackground))
            toolBar
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("完成") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: vm.undo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!vm.canUndo)
                    if vm.isExporting {
                        ProgressView()
                    } else {
                        Button("保存", action: save)
                    }
                }
            }
        }
        .alert("重新裁剪将清除已有的马赛克与标注", isPresented: $vm.showClearMarksAlert) {
            Button("清除并裁剪", role: .destructive) { vm.confirmCropClearingMarks() }
            Button("取消", role: .cancel) { vm.cancelPendingCrop() }
        }
        .alert(didSave ? "已保存到相册" : "保存失败", isPresented: $showSaveResult) {
            Button("好", role: .cancel) {}
        }
    }

    // MARK: - Preview

    private var previewArea: some View {
        GeometryReader { geo in
            let displayRect = aspectFitRect(imageSize: vm.preview.size, in: geo.size)
            ZStack {
                Color(uiColor: .systemBackground)
                Image(uiImage: vm.preview)
                    .resizable()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)
                overlay(displayRect: displayRect)
            }
            .onAppear { syncDisplayRect(displayRect) }
            .onChange(of: displayRect) { syncDisplayRect($0) }
            .onChange(of: vm.activeTool) { _ in resetCropDraft() }
        }
    }

    @ViewBuilder
    private func overlay(displayRect: CGRect) -> some View {
        switch vm.activeTool {
        case .crop:
            CropOverlay(displayRect: displayRect, draft: $cropDraft)
        case .mosaic:
            MosaicCanvas(displayRect: displayRect, widthFraction: brushWidth) { points in
                vm.addMosaicStroke(MosaicStroke(points: points, widthFraction: brushWidth, style: mosaicStyle))
            }
        case .annotate:
            AnnotateCanvas(displayRect: displayRect,
                           kind: annotationKind,
                           color: annotationColor,
                           widthFraction: annotationWidth) { points in
                vm.addAnnotation(AnnotationItem(kind: annotationKind,
                                                color: annotationColor,
                                                widthFraction: annotationWidth,
                                                points: points))
            }
        case .watermark, .border, .shell, .statusBar:
            EmptyView()
        }
    }

    // MARK: - Tool bar

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    Button(action: { vm.selectTool(tool) }) {
                        VStack(spacing: 4) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 18))
                            Text(tool.displayName)
                                .font(.caption2)
                        }
                        .frame(width: 58, height: 52)
                        .foregroundColor(vm.activeTool == tool ? .accentColor : .primary)
                        .background(vm.activeTool == tool ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 60)
    }

    // MARK: - Crop

    private func syncDisplayRect(_ rect: CGRect) {
        let changed = lastDisplayRect != rect
        lastDisplayRect = rect
        if changed, vm.activeTool == .crop { resetCropDraft() }
    }

    /// 把模型中的裁剪矩形（预览像素）映射到视图坐标；无裁剪时草稿为整幅。
    private func resetCropDraft() {
        guard vm.activeTool == .crop, let displayRect = lastDisplayRect else {
            cropDraft = nil
            return
        }
        let base = vm.model.base.size
        guard base.width > 0, base.height > 0 else { return }
        if let crop = vm.model.cropRect {
            let scale = displayRect.width / base.width
            cropDraft = CGRect(x: displayRect.minX + crop.minX * scale,
                               y: displayRect.minY + crop.minY * scale,
                               width: crop.width * scale,
                               height: crop.height * scale)
        } else {
            cropDraft = displayRect
        }
    }

    private func applyCrop() {
        guard let draft = cropDraft, let displayRect = lastDisplayRect else { return }
        let base = vm.model.base.size
        guard base.width > 0 else { return }
        let scale = base.width / displayRect.width
        let rect = CGRect(x: (draft.minX - displayRect.minX) * scale,
                          y: (draft.minY - displayRect.minY) * scale,
                          width: draft.width * scale,
                          height: draft.height * scale)
            .integral
            .intersection(CGRect(origin: .zero, size: base))
        guard rect.width >= 2, rect.height >= 2 else { return }
        vm.commitCrop(rect == CGRect(origin: .zero, size: base) ? nil : rect)
    }

    // MARK: - Save

    private func save() {
        vm.isExporting = true
        Task {
            let image = await vm.exportImage()
            await MainActor.run { vm.isExporting = false }
            service.saveToPhotoLibrary(image) { success in
                DispatchQueue.main.async {
                    didSave = success
                    showSaveResult = true
                }
            }
        }
    }
}
