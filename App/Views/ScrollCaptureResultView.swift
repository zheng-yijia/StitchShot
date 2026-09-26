import SwiftUI
import PhotoLibraryKit
import ScrollCaptureKit
import StitchCore

/// 滚动截图结果：从会话条带合成长图 → 预览 → 保存相册 → 清理会话数据。
struct ScrollCaptureResultView: View {
    let sessionID: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var didSave = false

    private let service = PhotoLibraryService()

    init(sessionID: String, onDismiss: @escaping () -> Void = {}) {
        self.sessionID = sessionID
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            Group {
                if let image {
                    ScrollView([.vertical, .horizontal]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ProgressView("正在合成长图…")
                }
            }
            .navigationTitle("长截图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSave ? "关闭" : "丢弃") {
                        cleanup()
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(didSave ? "已保存" : "保存到相册") { save() }
                        .disabled(image == nil || didSave)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await compose() }
    }

    private func compose() async {
        guard let composed = await ScrollCaptureComposer.compose(sessionID: sessionID) else {
            errorMessage = "合成失败：会话数据不存在或已损坏"
            return
        }
        image = composed
    }

    private func save() {
        guard let image else { return }
        service.saveToPhotoLibrary(image) { success in
            DispatchQueue.main.async {
                didSave = success
                if success { cleanup() }
            }
        }
    }

    private func cleanup() {
        ScrollCaptureComposer.deleteSession(id: sessionID)
        ScrollCaptureStatusStore.reset()
    }
}
