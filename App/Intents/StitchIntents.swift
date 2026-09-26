import AppIntents
import PhotoLibraryKit
import Photos
import StitchCore
import StitchEngine
import UIKit

// App Intents 需要 iOS 16+；iOS 15 设备走 URL Scheme 自动化。

@available(iOS 16.0, *)
enum StitchDirectionAppEnum: String, AppEnum {
    case vertical
    case horizontal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "拼接方向"

    static let caseDisplayRepresentations: [StitchDirectionAppEnum: DisplayRepresentation] = [
        .vertical: "纵向（长截图）",
        .horizontal: "横向"
    ]

    var stitchDirection: StitchDirection {
        switch self {
        case .vertical: return .vertical
        case .horizontal: return .horizontal
        }
    }
}

// MARK: - 拼接最新截图

@available(iOS 16.0, *)
struct StitchLatestScreenshotsIntent: AppIntent {
    static let title: LocalizedStringResource = "拼接最新截图"
    static let description = IntentDescription("自动获取相册中最近的几张截图并拼接成长图，保存回相册。")

    @Parameter(title: "张数", default: 2)
    var count: Int

    @Parameter(title: "方向", default: .vertical)
    var direction: StitchDirectionAppEnum

    @Parameter(title: "清理状态栏", default: true)
    var cleanStatus: Bool

    @Parameter(title: "带壳截图", default: false)
    var mockup: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        var status = PhotoAuthorization.currentStatus
        if status == .notDetermined {
            status = await PhotoAuthorization.requestAccess()
        }
        guard status == .authorized || status == .limited else {
            throw AutomationIntentError.noPhotoAccess
        }

        let service = PhotoLibraryService()
        let fetchResult = service.fetchAssets(filter: .screenshots)
        let take = min(max(2, count), fetchResult.count)
        guard take >= 2 else { throw AutomationIntentError.notEnoughImages }

        var images: [UIImage] = []
        for index in stride(from: take - 1, through: 0, by: -1) {
            let asset = fetchResult.object(at: index)
            if let image = await Self.fullImage(for: asset, service: service) {
                images.append(image)
            }
        }
        guard images.count >= 2 else { throw AutomationIntentError.notEnoughImages }

        guard let result = await StitchAutomation.stitch(
            images: images, direction: direction.stitchDirection,
            cleanStatus: cleanStatus, mockup: mockup
        ) else {
            throw AutomationIntentError.stitchFailed
        }

        try await saveToPhotos(result)
        guard let data = result.pngData() else { throw AutomationIntentError.stitchFailed }
        let file = IntentFile(data: data, filename: "stitched.png", type: .png)
        return .result(value: file, dialog: "已拼接 \(images.count) 张截图并保存到相册")
    }

    private static func fullImage(for asset: PHAsset, service: PhotoLibraryService) async -> UIImage? {
        await withCheckedContinuation { continuation in
            service.requestFullImageData(for: asset) { data in
                continuation.resume(returning: data.flatMap { UIImage(data: $0) })
            }
        }
    }
}

// MARK: - 拼接传入图片

@available(iOS 16.0, *)
struct StitchImagesIntent: AppIntent {
    static let title: LocalizedStringResource = "拼接图片"
    static let description = IntentDescription("把传入的多张图片按指定方向拼接为一张长图。")

    @Parameter(title: "图片")
    var images: [IntentFile]

    @Parameter(title: "方向", default: .vertical)
    var direction: StitchDirectionAppEnum

    @Parameter(title: "清理状态栏", default: false)
    var cleanStatus: Bool

    @Parameter(title: "带壳截图", default: false)
    var mockup: Bool

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let loaded = images.compactMap { UIImage(data: $0.data) }
        guard loaded.count >= 2 else { throw AutomationIntentError.notEnoughImages }
        guard let result = await StitchAutomation.stitch(
            images: loaded, direction: direction.stitchDirection,
            cleanStatus: cleanStatus, mockup: mockup
        ) else {
            throw AutomationIntentError.stitchFailed
        }
        guard let data = result.pngData() else { throw AutomationIntentError.stitchFailed }
        let file = IntentFile(data: data, filename: "stitched.png", type: .png)
        return .result(value: file, dialog: "已拼接 \(loaded.count) 张图片")
    }
}

// MARK: - 打开滚动截图

@available(iOS 16.0, *)
struct OpenScrollCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "打开滚动截图"
    static let description = IntentDescription("打开 StitchShot 的滚动截图页，准备开始录屏拼接。")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        URLRouter.setPendingRoute(.scroll)
        return .result()
    }
}

// MARK: - 错误

@available(iOS 16.0, *)
enum AutomationIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noPhotoAccess
    case notEnoughImages
    case stitchFailed
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noPhotoAccess: return "没有相册访问权限"
        case .notEnoughImages: return "可用图片不足 2 张"
        case .stitchFailed: return "拼接失败"
        case .saveFailed: return "保存到相册失败"
        }
    }
}

@available(iOS 16.0, *)
private func saveToPhotos(_ image: UIImage) async throws {
    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
    }
}

// MARK: - Shortcuts 注册

@available(iOS 16.0, *)
struct StitchShotAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StitchLatestScreenshotsIntent(),
            phrases: [
                "用 \(.applicationName) 拼接最新截图",
                "拼接最新截图 \(.applicationName)"
            ],
            shortTitle: "拼接最新截图",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: StitchImagesIntent(),
            phrases: [
                "用 \(.applicationName) 拼接图片",
                "拼接图片 \(.applicationName)"
            ],
            shortTitle: "拼接图片",
            systemImageName: "photo.on.rectangle"
        )
        AppShortcut(
            intent: OpenScrollCaptureIntent(),
            phrases: [
                "用 \(.applicationName) 滚动截图",
                "开始滚动截图 \(.applicationName)"
            ],
            shortTitle: "滚动截图",
            systemImageName: "scroll"
        )
    }
}
