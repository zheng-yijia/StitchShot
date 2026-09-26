import PhotoLibraryKit
import Photos
import StitchCore
import StitchEngine
import UIKit

/// x-callback-url 自动化：
/// stitchshot://x-callback-url/vert|hori?in=clipboard|latest&count=N&out=clipboard|save|x-callback-url
///   &delete_source=0|1&mockup=0|1&clean_status=0|1&x-success=URL&x-error=URL
/// stitchshot://x-callback-url/scroll 仅打开滚动截图页（录屏无法自动完成）。
enum AutomationService {

    static let completionNotification = Notification.Name("StitchShot.AutomationCompleted")

    // MARK: - 请求解析

    struct Request {
        enum Action: String {
            case vert, hori, scroll
        }
        enum Input {
            case clipboard
            case latest(Int)
        }
        enum Output {
            case clipboard, save, callback
        }

        var action: Action
        var input: Input = .clipboard
        var output: Output = .save
        var deleteSource = false
        var mockup = false
        var cleanStatus = false
        var successURL: URL?
        var errorURL: URL?

        init?(url: URL) {
            guard url.host == "x-callback-url" else { return nil }
            let actionName = url.pathComponents.dropFirst().first
            guard let raw = actionName, let action = Action(rawValue: raw) else { return nil }
            self.action = action

            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? {
                items.first { $0.name == name }?.value
            }
            func flag(_ name: String) -> Bool {
                value(name).map { $0 == "1" || $0.lowercased() == "true" || $0.lowercased() == "yes" } ?? false
            }

            switch value("in") {
            case "latest":
                let count = max(2, min(30, Int(value("count") ?? "") ?? 2))
                input = .latest(count)
            default:
                input = .clipboard
            }
            switch value("out") {
            case "clipboard": output = .clipboard
            case "x-callback-url", "callback": output = .callback
            default: output = .save
            }
            deleteSource = flag("delete_source")
            mockup = flag("mockup")
            cleanStatus = flag("clean_status")
            if let success = value("x-success") { successURL = URL(string: success) }
            if let failure = value("x-error") { errorURL = URL(string: failure) }
        }
    }

    // MARK: - 入口

    static func handle(_ url: URL) {
        guard let request = Request(url: url) else { return }
        if request.action == .scroll {
            NotificationCenter.default.post(name: URLRouter.switchTabNotification, object: AppRoute.scroll)
            return
        }
        Task { await execute(request) }
    }

    // MARK: - 执行

    private static func execute(_ request: Request) async {
        let direction: StitchDirection = request.action == .vert ? .vertical : .horizontal

        var images: [UIImage] = []
        var sourceAssets: [PHAsset] = []
        switch request.input {
        case .clipboard:
            images = await MainActor.run { UIPasteboard.general.images ?? [] }
        case .latest(let count):
            let loaded = await latestScreenshots(count: count)
            images = loaded.images
            sourceAssets = loaded.assets
        }

        guard images.count >= 2 else {
            fail(request, code: 1, message: "可用图片不足 2 张")
            return
        }

        guard let result = await StitchAutomation.stitch(
            images: images,
            direction: direction,
            cleanStatus: request.cleanStatus,
            mockup: request.mockup
        ) else {
            fail(request, code: 2, message: "拼接失败")
            return
        }

        switch request.output {
        case .save:
            let saved = await saveToPhotos(result)
            guard saved else {
                fail(request, code: 3, message: "保存到相册失败")
                return
            }
        case .clipboard, .callback:
            await MainActor.run { UIPasteboard.general.image = result }
        }

        if request.deleteSource, !sourceAssets.isEmpty {
            await deleteAssets(sourceAssets)
        }

        postCompletion("拼接完成（\(images.count) 张）")
        if let success = request.successURL {
            await MainActor.run { UIApplication.shared.open(success) }
        }
    }

    // MARK: - 相册

    private static func latestScreenshots(count: Int) async -> (images: [UIImage], assets: [PHAsset]) {
        var status = PhotoAuthorization.currentStatus
        if status == .notDetermined {
            status = await PhotoAuthorization.requestAccess()
        }
        guard status == .authorized || status == .limited else { return ([], []) }

        let service = PhotoLibraryService()
        let fetchResult = service.fetchAssets(filter: .screenshots)
        let take = min(count, fetchResult.count)
        guard take >= 2 else { return ([], []) }

        // fetchResult 按创建时间倒序；拼接需正序（旧→新）
        let assets = (0..<take).map { fetchResult.object(at: $0) }.reversed()
        var images: [UIImage] = []
        var keptAssets: [PHAsset] = []
        for asset in assets {
            if let image = await fullImage(for: asset, service: service) {
                images.append(image)
                keptAssets.append(asset)
            }
        }
        return (images, keptAssets)
    }

    private static func fullImage(for asset: PHAsset, service: PhotoLibraryService) async -> UIImage? {
        await withCheckedContinuation { continuation in
            service.requestFullImageData(for: asset) { data in
                continuation.resume(returning: data.flatMap { UIImage(data: $0) })
            }
        }
    }

    private static func saveToPhotos(_ image: UIImage) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private static func deleteAssets(_ assets: [PHAsset]) async {
        _ = try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    // MARK: - 回调与提示

    private static func fail(_ request: Request, code: Int, message: String) {
        postCompletion("自动化失败：\(message)")
        guard var components = request.errorURL.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "errorCode", value: "\(code)"))
        items.append(URLQueryItem(name: "errorMessage", value: message))
        components.queryItems = items
        if let url = components.url {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
    }

    private static func postCompletion(_ message: String) {
        NotificationCenter.default.post(name: completionNotification, object: message)
    }
}
