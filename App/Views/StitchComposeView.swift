import SwiftUI
import Photos
import PhotoLibraryKit
import StitchCore
import StitchEngine

/// 拼接预览：自动检测重叠 → 渲染长图；低置信接缝可进入手动微调。
struct StitchComposeView: View {
    enum Source {
        case assets([PHAsset])
        case images([UIImage])
    }

    let source: Source
    let direction: StitchDirection
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var plan: StitchPlan?
    @State private var result: UIImage?
    @State private var isRendering = false
    @State private var didSave = false
    @State private var errorMessage: String?
    @State private var showAdjustment = false

    @AppStorage("settings.cleanStatusBar", store: AppConstants.sharedDefaults)
    private var cleanStatusBar = true
    @AppStorage("settings.deleteSourceAfterStitch", store: AppConstants.sharedDefaults)
    private var deleteSourceAfterStitch = false

    private let service = PhotoLibraryService()

    init(assets: [PHAsset], direction: StitchDirection, onSaved: (() -> Void)? = nil) {
        self.source = .assets(assets)
        self.direction = direction
        self.onSaved = onSaved
    }

    init(images: [UIImage], direction: StitchDirection, onSaved: (() -> Void)? = nil) {
        self.source = .images(images)
        self.direction = direction
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationView {
            Group {
                if let result {
                    resultContent(result)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ProgressView("正在分析重叠区域…")
                }
            }
            .navigationTitle("拼接预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(didSave ? "已保存" : "保存") { save() }
                        .disabled(result == nil || didSave || isRendering)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await generate() }
        .sheet(isPresented: $showAdjustment) {
            if let plan {
                SeamAdjustmentView(images: images, plan: plan) { adjusted in
                    self.plan = adjusted
                    Task { await renderNow() }
                }
            }
        }
    }

    private func resultContent(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            if let plan, !plan.problematicSeamIndices.isEmpty {
                Button { showAdjustment = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(plan.problematicSeamIndices.count) 处接缝未能自动对齐，点此手动调整")
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(.orange)
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                }
            }

            ScrollView([.vertical, .horizontal]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }

            if plan != nil {
                Divider()
                HStack {
                    Button { showAdjustment = true } label: {
                        Label("调整拼接", systemImage: "slider.horizontal.3")
                    }
                    .disabled(isRendering)
                    Spacer()
                    if isRendering {
                        ProgressView()
                    }
                }
                .padding()
            }
        }
    }

    private func generate() async {
        let loaded: [UIImage]
        switch source {
        case .images(let provided):
            loaded = provided
        case .assets(let assets):
            var fromLibrary: [UIImage] = []
            for asset in assets {
                if let image = await fullImage(for: asset) {
                    fromLibrary.append(image)
                }
            }
            guard fromLibrary.count == assets.count else {
                errorMessage = "图片加载失败，请重试"
                return
            }
            loaded = fromLibrary
        }
        guard loaded.count > 1 else {
            errorMessage = "图片数量不足，无法拼接"
            return
        }
        var working = loaded
        if cleanStatusBar {
            working = await Task.detached(priority: .userInitiated) {
                loaded.map { StitchAutomation.cleanStatusBar($0) }
            }.value
        }
        let analyzed = await StitchEngine.analyze(images: working, direction: direction)
        images = working
        plan = analyzed
        await renderNow()
    }

    private func renderNow() async {
        guard let plan else { return }
        isRendering = true
        let rendered = await StitchEngine.render(plan: plan, images: images)
        isRendering = false
        guard let rendered else {
            errorMessage = "拼接失败"
            return
        }
        result = rendered
    }

    private func fullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            service.requestFullImageData(for: asset) { data in
                continuation.resume(returning: data.flatMap { UIImage(data: $0) })
            }
        }
    }

    private func save() {
        guard let result else { return }
        service.saveToPhotoLibrary(result) { success in
            DispatchQueue.main.async {
                didSave = success
                if success {
                    onSaved?()
                    deleteSourcesIfNeeded()
                }
            }
        }
    }

    private func deleteSourcesIfNeeded() {
        guard deleteSourceAfterStitch, case .assets(let assets) = source, !assets.isEmpty else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        } completionHandler: { _, _ in }
    }
}
