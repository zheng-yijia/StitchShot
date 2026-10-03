import AVFoundation
import LivePhotoKit
import PhotoLibraryKit
import Photos
import PhotosUI
import SwiftUI

/// 视频转实况照片：截取 ≤5 秒片段（可来回循环），生成并保存 Live Photo。
struct LivePhotoMakerView: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var avAsset: AVAsset?
    @State private var duration: Double = 0
    @State private var trimStart: Double = 0
    @State private var trimLength: Double = 3
    @State private var loopMode: LivePhotoLoopMode = .trim
    @State private var isConverting = false
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?
    @State private var livePhoto: PHLivePhoto?
    @State private var result: LivePhotoResult?

    private let service = PhotoLibraryService()

    var body: some View {
        NavigationView {
            Group {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .padding()
                } else if avAsset == nil {
                    ProgressView("正在读取视频…")
                } else {
                    content
                }
            }
            .navigationTitle("视频转实况照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if result != nil {
                        Button(didSave ? "已保存" : "保存") { save() }
                            .disabled(didSave || isSaving)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await loadAsset() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                if let livePhoto {
                    VStack(spacing: 6) {
                        LivePhotoPreview(livePhoto: livePhoto)
                            .frame(height: 280)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(12)
                        Text("长按预览实况效果")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                controls
                if isConverting {
                    ProgressView("正在转换…")
                }
                convertButton
            }
            .padding()
        }
    }

    private var preview: some View {
        VideoPoster(asset: asset, service: service)
            .frame(height: 220)
            .background(Color.black.opacity(0.05))
            .cornerRadius(12)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("起点")
                    .font(.subheadline)
                    .frame(width: 40, alignment: .leading)
                Slider(value: $trimStart, in: 0...max(0.1, duration - 0.5), step: 0.1)
                    .onChange(of: trimStart) { _ in clampRange() }
                Text(timeText(trimStart))
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Text("时长")
                    .font(.subheadline)
                    .frame(width: 40, alignment: .leading)
                Slider(value: $trimLength, in: 0.5...max(0.5, min(LivePhotoConverter.maxDurationSeconds, max(duration, 0.5))), step: 0.1)
                    .onChange(of: trimLength) { _ in clampRange() }
                Text(timeText(trimLength))
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }
            Picker("模式", selection: $loopMode) {
                ForEach(LivePhotoLoopMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: loopMode) { _ in
                resetConvertedResult()
            }
        }
    }

    private var convertButton: some View {
        Button {
            convert()
        } label: {
            Label(result == nil ? "开始转换" : "重新转换", systemImage: "livephoto")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isConverting)
    }

    // MARK: - Actions

    private func loadAsset() async {
        let loaded = await withCheckedContinuation { continuation in
            service.requestAVAsset(for: asset) { continuation.resume(returning: $0) }
        }
        guard let loaded else {
            errorMessage = "无法读取视频，请重试"
            return
        }
        avAsset = loaded
        let seconds = loaded.duration.seconds
        duration = seconds.isFinite && seconds > 0 ? seconds : 0
        trimStart = 0
        trimLength = min(3, max(0.5, duration))
    }

    private func clampRange() {
        trimStart = min(max(0, trimStart), max(0, duration - 0.5))
        let maxLength = max(0.5, min(LivePhotoConverter.maxDurationSeconds, duration - trimStart))
        trimLength = min(max(0.5, trimLength), maxLength)
        resetConvertedResult()
    }

    private func resetConvertedResult() {
        result = nil
        livePhoto = nil
        didSave = false
    }

    private func convert() {
        guard let avAsset, !isConverting else { return }
        isConverting = true
        errorMessage = nil
        resetConvertedResult()

        var options = LivePhotoOptions()
        options.trimStart = CMTime(seconds: trimStart, preferredTimescale: 600)
        options.trimDuration = CMTime(seconds: trimLength, preferredTimescale: 600)
        options.loopMode = loopMode

        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try LivePhotoConverter.convert(asset: avAsset, options: options)
                }.value
                result = output
                loadLivePhotoPreview(output)
            } catch {
                errorMessage = error.localizedDescription
            }
            isConverting = false
        }
    }

    private func loadLivePhotoPreview(_ output: LivePhotoResult) {
        _ = PHLivePhoto.request(
            withResourceFileURLs: [output.videoURL, output.photoURL],
            placeholderImage: nil,
            targetSize: CGSize(width: 600, height: 600),
            contentMode: .aspectFit
        ) { photo, _ in
            DispatchQueue.main.async {
                if let photo { livePhoto = photo }
            }
        }
    }

    private func save() {
        guard let result, !isSaving else { return }
        isSaving = true
        service.saveLivePhoto(photoURL: result.photoURL, videoURL: result.videoURL) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    didSave = true
                    cleanupTempFiles(result)
                } else {
                    errorMessage = "保存失败，请重试"
                }
            }
        }
    }

    private func cleanupTempFiles(_ result: LivePhotoResult) {
        let directory = result.photoURL.deletingLastPathComponent()
        guard directory.lastPathComponent.hasPrefix("StitchShotLivePhoto-") else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}

private struct VideoPoster: View {
    let asset: PHAsset
    let service: PhotoLibraryService

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        service.requestThumbnail(for: asset, targetSize: CGSize(width: 800, height: 800)) { loaded in
            DispatchQueue.main.async { image = loaded }
        }
    }
}

private struct LivePhotoPreview: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ uiView: PHLivePhotoView, context: Context) {
        uiView.livePhoto = livePhoto
    }
}
