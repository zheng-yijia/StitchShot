import PhotoLibraryKit
import Photos
import SwiftUI

/// 视频选择器：选择相册视频后回调 PHAsset。
struct VideoPickerSheet: View {
    var onPick: (PHAsset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: PHFetchResult<PHAsset>?
    @State private var authorized = false

    private let service = PhotoLibraryService()
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationView {
            content
                .navigationTitle("选择视频")
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
        if !authorized {
            Text("请在系统设置中允许访问照片")
                .foregroundColor(.secondary)
        } else if let assets, assets.count > 0 {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<assets.count, id: \.self) { index in
                        VideoPickerCell(asset: assets.object(at: index), service: service) {
                            onPick(assets.object(at: index))
                        }
                    }
                }
            }
        } else {
            Text("相册暂无视频")
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
            assets = service.fetchVideoAssets()
        }
    }
}

private struct VideoPickerCell: View {
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
            .overlay(alignment: .bottomTrailing) {
                Text(durationText)
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onAppear(perform: load)
    }

    private var durationText: String {
        let total = Int(asset.duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func load() {
        let scale = UIScreen.main.scale
        let size = CGSize(width: 140 * scale, height: 140 * scale)
        service.requestThumbnail(for: asset, targetSize: size) { loaded in
            DispatchQueue.main.async { image = loaded }
        }
    }
}
