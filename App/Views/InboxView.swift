import ImageEditorKit
import PhotoLibraryKit
import StitchCore
import SwiftUI

/// 共享收件箱：来自 Share / Action / Safari 扩展的图片，可拼接、编辑或保存。
struct InboxView: View {

    private struct ComposeTarget: Identifiable {
        let id = UUID()
        let items: [InboxItem]
        let images: [UIImage]
    }

    private struct EditTarget: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @Environment(\.dismiss) private var dismiss
    @State private var items: [InboxItem] = []
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var selectedIDs: [UUID] = []
    @State private var composeTarget: ComposeTarget?
    @State private var editTarget: EditTarget?
    @State private var isWorking = false
    @State private var showClearConfirm = false

    private let photoService = PhotoLibraryService()

    var body: some View {
        NavigationView {
            Group {
                if items.isEmpty {
                    emptyGuide
                } else {
                    List {
                        ForEach(items) { item in
                            row(for: item)
                                .contentShape(Rectangle())
                                .onTapGesture { toggleSelection(item) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("收件箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !items.isEmpty {
                        Button("清空") { showClearConfirm = true }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !items.isEmpty {
                        HStack {
                            if isWorking { ProgressView() }
                            Spacer()
                            Button("拼接已选 \(selectedIDs.count) 张") { composeSelected() }
                                .buttonStyle(.borderedProminent)
                                .disabled(selectedIDs.count < 2 || isWorking)
                        }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { reload() }
        .confirmationDialog("删除收件箱全部图片？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("全部删除", role: .destructive) {
                SharedInbox.removeAll()
                selectedIDs = []
                reload()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(item: $composeTarget) { target in
            StitchComposeView(images: target.images, direction: .vertical) {
                target.items.forEach { SharedInbox.remove($0) }
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
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("收件箱为空")
                .font(.headline)
            Text("在其他 App 中通过「分享」或「用 StitchShot 打开」\n把图片送到这里，再统一拼接或编辑。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for item: InboxItem) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Color.secondary.opacity(0.12)
                    .frame(width: 56, height: 56)
                    .overlay {
                        if let thumb = thumbnails[item.id] {
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let order = selectedIDs.firstIndex(of: item.id) {
                    Text("\(order + 1)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.accentColor))
                        .offset(x: 5, y: -5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceLabel(item.source))
                    .font(.body)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button { edit(item) } label: { Label("编辑", systemImage: "pencil") }
                Button { save(item) } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
                Button(role: .destructive) { delete(item) } label: { Label("删除", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "share": return "来自分享"
        case "action": return "来自操作扩展"
        case "safari": return "来自 Safari"
        default: return "导入图片"
        }
    }

    private func toggleSelection(_ item: InboxItem) {
        if let index = selectedIDs.firstIndex(of: item.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(item.id)
        }
    }

    private func reload() {
        items = SharedInbox.pendingItems()
        loadThumbnails()
    }

    private func loadThumbnails() {
        let current = items
        Task.detached(priority: .utility) {
            var map: [UUID: UIImage] = [:]
            for item in current {
                autoreleasepool {
                    guard let data = try? Data(contentsOf: item.fileURL),
                          let image = UIImage(data: data) else { return }
                    map[item.id] = Self.thumbnail(image, maxSide: 168)
                }
            }
            await MainActor.run { thumbnails = map }
        }
    }

    private static func thumbnail(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxSide else { return image }
        let scale = maxSide / max(size.width, size.height)
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func composeSelected() {
        let chosen = selectedIDs.compactMap { id in items.first { $0.id == id } }
        guard chosen.count > 1 else { return }
        isWorking = true
        Task.detached(priority: .userInitiated) {
            let images = chosen.compactMap { item -> UIImage? in
                autoreleasepool {
                    guard let data = try? Data(contentsOf: item.fileURL) else { return nil }
                    return UIImage(data: data)
                }
            }
            await MainActor.run {
                isWorking = false
                guard images.count == chosen.count else { return }
                selectedIDs = []
                composeTarget = ComposeTarget(items: chosen, images: images)
            }
        }
    }

    private func edit(_ item: InboxItem) {
        guard let data = try? Data(contentsOf: item.fileURL),
              let image = UIImage(data: data) else { return }
        editTarget = EditTarget(image: image)
    }

    private func save(_ item: InboxItem) {
        guard let data = try? Data(contentsOf: item.fileURL),
              let image = UIImage(data: data) else { return }
        photoService.saveToPhotoLibrary(image) { success in
            DispatchQueue.main.async {
                if success {
                    SharedInbox.remove(item)
                    reload()
                }
            }
        }
    }

    private func delete(_ item: InboxItem) {
        SharedInbox.remove(item)
        selectedIDs.removeAll { $0 == item.id }
        reload()
    }

    private func delete(at offsets: IndexSet) {
        offsets.map { items[$0] }.forEach { SharedInbox.remove($0) }
        reload()
    }
}
