import AVFoundation
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

    // MARK: - 视频

    public func fetchVideoAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        return PHAsset.fetchAssets(with: options)
    }

    public func requestAVAsset(for asset: PHAsset, completion: @escaping (AVAsset?) -> Void) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            completion(avAsset)
        }
    }

    /// 将 still.jpg + video.mov 保存为一枚系统实况照片。
    public func saveLivePhoto(photoURL: URL, videoURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: photoURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: videoURL, options: nil)
        } completionHandler: { success, _ in
            completion(success)
        }
    }
}
