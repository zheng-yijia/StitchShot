import Photos
import UIKit

public enum PhotoAuthorization {
    public static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    public static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}

/// 相册读取与图片加载（带缓存）。所有拼接流程的图片来源都经由这里。
public final class PhotoLibraryService {
    public enum AlbumFilter {
        case screenshots
        case allPhotos
    }

    private let cachingManager = PHCachingImageManager()

    public init() {}

    public func fetchAssets(filter: AlbumFilter) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        switch filter {
        case .screenshots:
            let collections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
            guard let album = collections.firstObject else {
                return PHAsset.fetchAssets(with: .image, options: PHFetchOptions())
            }
            return PHAsset.fetchAssets(in: album, options: options)
        case .allPhotos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return PHAsset.fetchAssets(with: options)
        }
    }

    @discardableResult
    public func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return cachingManager.requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !degraded { completion(image) }
            else if image != nil { completion(image) }
        }
    }

    public func cancelThumbnailRequest(_ id: PHImageRequestID) {
        cachingManager.cancelImageRequest(id)
    }

    /// 原图数据，供拼接引擎使用。
    public func requestFullImageData(
        for asset: PHAsset,
        completion: @escaping (Data?) -> Void
    ) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        cachingManager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            completion(data)
        }
    }

    public func saveToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, _ in
            completion(success)
        }
    }
}
