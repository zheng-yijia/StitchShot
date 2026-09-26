import PhotoLibraryKit
import Photos
import SwiftUI

/// 单选图片选择器：选择后回调原图。
struct ImagePickerSheet: View {
    var onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: PHFetchResult<PHAsset>?
    @State private var authorized = false
    @State private var isLoading = false

    private let service = PhotoLibraryService()
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            content
                .navigationTitle("选择图片")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { dismiss() }
                    }
                }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("正在读取图片…")
        } else if !authorized {
            Text("请在系统设置中允许访问照片")
                .foregroundColor(.secondary)
        } else if let assets, assets.count > 0 {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<assets.count, id: \.self) { index in
                        PickerCell(asset: assets.object(at: index), service: service) {
                            pick(assets.object(at: index))
                        }
                    }
                }
            }
        } else {
            Text("相册暂无图片")
                .foregroundColor(.secondary)
        }
    }

    private func load() async {
        var status = PhotoAuthorization.currentStatus
        if status == .notDetermined {
            status = await PhotoAuthorization.requestAccess()
        }
        authorized = status == .authorized || status == .limited
        if authorized {
            assets = service.fetchAssets(filter: .allPhotos)
        }
    }

    private func pick(_ asset: PHAsset) {
        isLoading = true
        service.requestFullImageData(for: asset) { data in
            DispatchQueue.main.async {
                isLoading = false
                guard let data, let image = UIImage(data: data) else { return }
                onPick(image)
            }
        }
    }
}

private struct PickerCell: View {
    let asset: PHAsset
    let service: PhotoLibraryService
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onAppear(perform: load)
    }

    private func load() {
        let scale = UIScreen.main.scale
        let size = CGSize(width: 140 * scale, height: 140 * scale)
        service.requestThumbnail(for: asset, targetSize: size) { loaded in
            DispatchQueue.main.async { image = loaded }
        }
    }
}
