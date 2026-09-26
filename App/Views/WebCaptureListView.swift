import ImageEditorKit
import StitchCore
import SwiftUI

/// Safari 整页捕获会话列表：选择一组帧进行拼接，或单帧直接编辑保存。
struct WebCaptureListView: View {

    private struct ComposeTarget: Identifiable {
        let id = UUID()
        let sessionID: String
        let images: [UIImage]
    }

    private struct EditTarget: Identifiable {
        let id = UUID()
        let sessionID: String
        let image: UIImage
    }

    @State private var sessions: [WebCaptureSession] = []
    @State private var composeTarget: ComposeTarget?
    @State private var editTarget: EditTarget?
    @State private var isLoading = false
    @State private var showClearConfirm = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("正在读取帧…")
            } else if sessions.isEmpty {
                emptyGuide
            } else {
                List {
                    ForEach(sessions) { session in
                        sessionRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture { open(session) }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("网页快照")
        .toolbar {
            if !sessions.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { showClearConfirm = true }
                }
            }
        }
        .confirmationDialog("删除全部网页快照会话？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("全部删除", role: .destructive) {
                WebCaptureSessionStore.deleteAll()
                reload()
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { reload() }
        .sheet(item: $composeTarget) { target in
            StitchComposeView(images: target.images, direction: .vertical) {
                WebCaptureSessionStore.delete(id: target.sessionID)
                reload()
            }
        }
        .sheet(item: $editTarget) { target in
            NavigationView {
                ImageEditorView(original: target.image)
            }
            .navigationViewStyle(.stack)
        }
    }

    private var emptyGuide: some View {
        VStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无网页快照")
                .font(.headline)
            Text("在 Safari 中打开网页，点工具栏的 StitchShot 扩展，\n选择「截取整页长图」，完成后回到这里拼接。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sessionRow(_ session: WebCaptureSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.image")
                .font(.title3)
                .frame(width: 32)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(host(of: session.pageURL) ?? "网页快照")
                    .font(.body)
                Text("\(session.frameFiles.count) 屏 · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func host(of urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url.host
    }

    private func reload() {
        sessions = WebCaptureSessionStore.sessions()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            WebCaptureSessionStore.delete(id: sessions[index].id)
        }
        reload()
    }

    private func open(_ session: WebCaptureSession) {
        isLoading = true
        Task {
            let frames = await Task.detached(priority: .userInitiated) { () -> [UIImage] in
                WebCaptureSessionStore.loadFrames(session).compactMap { UIImage(data: $0) }
            }.value
            await MainActor.run {
                isLoading = false
                guard !frames.isEmpty else { return }
                if frames.count == 1 {
                    editTarget = EditTarget(sessionID: session.id, image: frames[0])
                } else {
                    composeTarget = ComposeTarget(sessionID: session.id, images: frames)
                }
            }
        }
    }
}
