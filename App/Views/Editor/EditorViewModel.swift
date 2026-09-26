import ImageEditorKit
import SwiftUI

/// 编辑器视图模型：编辑在 1600px 预览上进行，导出时按原图重放全部操作。
@MainActor
final class EditorViewModel: ObservableObject {

    enum Stage {
        case base, core, full
    }

    @Published var model: EditModel
    @Published private(set) var preview: UIImage
    @Published var activeTool: EditorTool
    @Published var isExporting = false
    @Published var showClearMarksAlert = false
    @Published var savedToast = false

    let original: UIImage
    private var undoStack: [EditModel] = []
    private var pendingCrop: CGRect?
    private var renderTask: Task<Void, Never>?

    init(original: UIImage, presetTool: EditorTool?) {
        let normalized = Self.redraw(original, maxDimension: .greatestFiniteMagnitude)
        self.original = normalized
        let previewBase = Self.redraw(normalized, maxDimension: 1600)
        self.model = EditModel(base: previewBase)
        self.preview = previewBase
        self.activeTool = presetTool ?? .crop
    }

    var canUndo: Bool { !undoStack.isEmpty }

    var exportScaleFactor: CGFloat {
        guard model.base.size.width > 0 else { return 1 }
        return original.size.width / model.base.size.width
    }

    // MARK: - Undo

    func undo() {
        guard let last = undoStack.popLast() else { return }
        model = last
        scheduleRender()
    }

    private func pushUndo() {
        undoStack.append(model)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    // MARK: - Tool

    func selectTool(_ tool: EditorTool) {
        activeTool = tool
        scheduleRender()
    }

    nonisolated static func stage(for tool: EditorTool) -> Stage {
        switch tool {
        case .crop: return .base
        case .mosaic, .annotate: return .core
        case .watermark, .border, .shell, .statusBar: return .full
        }
    }

    // MARK: - Crop

    /// rect 为预览图像素坐标；nil 表示去除裁剪。
    func commitCrop(_ rect: CGRect?) {
        if let rect, model.hasMarks, rect != model.cropRect {
            pendingCrop = rect
            showClearMarksAlert = true
            return
        }
        pushUndo()
        model.cropRect = rect
        scheduleRender()
    }

    func confirmCropClearingMarks() {
        guard let rect = pendingCrop else { return }
        pushUndo()
        model.cropRect = rect
        model.mosaicStrokes = []
        model.annotations = []
        pendingCrop = nil
        scheduleRender()
    }

    func cancelPendingCrop() {
        pendingCrop = nil
    }

    // MARK: - Marks

    func addMosaicStroke(_ stroke: MosaicStroke) {
        pushUndo()
        model.mosaicStrokes.append(stroke)
        scheduleRender()
    }

    func addAnnotation(_ item: AnnotationItem) {
        pushUndo()
        model.annotations.append(item)
        scheduleRender()
    }

    func removeLastMosaic() {
        guard !model.mosaicStrokes.isEmpty else { return }
        pushUndo()
        model.mosaicStrokes.removeLast()
        scheduleRender()
    }

    func removeLastAnnotation() {
        guard !model.annotations.isEmpty else { return }
        pushUndo()
        model.annotations.removeLast()
        scheduleRender()
    }

    // MARK: - Non-interactive configs

    func setWatermark(_ config: WatermarkConfig?) {
        pushUndo()
        model.watermark = config
        scheduleRender()
    }

    func updateWatermark(_ mutate: (inout WatermarkConfig) -> Void) {
        guard var config = model.watermark else { return }
        mutate(&config)
        model.watermark = config
        scheduleRender(debounce: true)
    }

    func setBorder(_ config: BorderConfig?) {
        pushUndo()
        model.border = config
        scheduleRender()
    }

    func updateBorder(_ mutate: (inout BorderConfig) -> Void) {
        guard var config = model.border else { return }
        mutate(&config)
        model.border = config
        scheduleRender(debounce: true)
    }

    func setShell(_ config: ShellConfig?) {
        pushUndo()
        model.shell = config
        scheduleRender()
    }

    func updateShell(_ mutate: (inout ShellConfig) -> Void) {
        guard var config = model.shell else { return }
        mutate(&config)
        model.shell = config
        scheduleRender(debounce: true)
    }

    func setStatusBarClean(_ config: StatusBarCleanConfig?) {
        pushUndo()
        model.statusBarClean = config
        scheduleRender()
    }

    func updateStatusBarClean(_ mutate: (inout StatusBarCleanConfig) -> Void) {
        guard var config = model.statusBarClean else { return }
        mutate(&config)
        model.statusBarClean = config
        scheduleRender(debounce: true)
    }

    // MARK: - Rendering

    func scheduleRender(debounce: Bool = false) {
        renderTask?.cancel()
        let snapshot = model
        let tool = activeTool
        renderTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if Task.isCancelled { return }
            }
            let rendered = await Task.detached(priority: .userInitiated) {
                Self.render(snapshot, stage: Self.stage(for: tool))
            }.value
            guard !Task.isCancelled else { return }
            self?.preview = rendered
        }
    }

    nonisolated static func render(_ model: EditModel, stage: Stage) -> UIImage {
        switch stage {
        case .base: return EditorRenderer.renderBase(model)
        case .core: return EditorRenderer.renderCore(model)
        case .full: return EditorRenderer.renderFull(model)
        }
    }

    /// 重绘为 .up 方向且限制最长边；maxDimension 足够大时仅做方向归一化。
    nonisolated static func redraw(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    // MARK: - Export

    /// 按原图分辨率重放全部编辑操作。
    func exportImage() async -> UIImage {
        let factor = exportScaleFactor
        var exportModel = model
        exportModel.base = original
        if let rect = model.cropRect {
            exportModel.cropRect = CGRect(x: rect.origin.x * factor,
                                          y: rect.origin.y * factor,
                                          width: rect.size.width * factor,
                                          height: rect.size.height * factor)
        }
        return await Task.detached(priority: .userInitiated) {
            EditorRenderer.renderFull(exportModel)
        }.value
    }
}
