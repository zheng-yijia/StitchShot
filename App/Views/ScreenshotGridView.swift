import SwiftUI
import Photos
import PhotoLibraryKit

struct ScreenshotGridView: View {
    @ObservedObject var viewModel: ScreenshotLibraryViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            if viewModel.assets.isEmpty {
                Text("暂无图片")
                    .foregroundColor(.secondary)
                    .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(viewModel.assets, id: \.localIdentifier) { asset in
                        ScreenshotCell(asset: asset, viewModel: viewModel)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ScreenshotCell: View {
    let asset: PHAsset
    @ObservedObject var viewModel: ScreenshotLibraryViewModel
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
            .overlay(alignment: .topTrailing) { selectionBadge }
            .overlay {
                if viewModel.isSelected(asset) {
                    Color.accentColor.opacity(0.15)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.toggleSelection(asset) }
            .onAppear(perform: load)
    }

    @ViewBuilder
    private var selectionBadge: some View {
        if let order = viewModel.selectionOrder(asset) {
            Text("\(order)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .padding(6)
        }
    }

    private func load() {
        let scale = UIScreen.main.scale
        let size = CGSize(width: 140 * scale, height: 140 * scale)
        viewModel.service.requestThumbnail(for: asset, targetSize: size) { loaded in
            DispatchQueue.main.async { image = loaded }
        }
    }
}
