import Photos
import SwiftUI
import PhotoLibraryKit

final class ScreenshotLibraryViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var filter: PhotoLibraryService.AlbumFilter = .screenshots
    @Published private(set) var selectedIDs: [String] = []

    let service = PhotoLibraryService()

    override init() {
        authorizationStatus = PhotoAuthorization.currentStatus
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func requestAccessAndLoad() {
        Task {
            let status = await PhotoAuthorization.requestAccess()
            await MainActor.run {
                authorizationStatus = status
            }
            if status == .authorized || status == .limited {
                await reload()
            }
        }
    }

    @MainActor
    func reload() {
        let result = service.fetchAssets(filter: filter)
        var list: [PHAsset] = []
        list.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        assets = list
        let existing = Set(list.map(\.localIdentifier))
        selectedIDs = selectedIDs.filter { existing.contains($0) }
    }

    func setFilter(_ newFilter: PhotoLibraryService.AlbumFilter) {
        guard newFilter != filter else { return }
        filter = newFilter
        Task { await reload() }
    }

    func isSelected(_ asset: PHAsset) -> Bool {
        selectedIDs.contains(asset.localIdentifier)
    }

    /// 选择顺序（从 1 开始），未选中返回 nil。
    func selectionOrder(_ asset: PHAsset) -> Int? {
        selectedIDs.firstIndex(of: asset.localIdentifier).map { $0 + 1 }
    }

    func toggleSelection(_ asset: PHAsset, limit: Int = 30) {
        if let index = selectedIDs.firstIndex(of: asset.localIdentifier) {
            selectedIDs.remove(at: index)
        } else if selectedIDs.count < limit {
            selectedIDs.append(asset.localIdentifier)
        }
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    var selectedAssets: [PHAsset] {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        return selectedIDs.compactMap { byID[$0] }
    }

    // MARK: - PHPhotoLibraryChangeObserver

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { await reload() }
    }
}
