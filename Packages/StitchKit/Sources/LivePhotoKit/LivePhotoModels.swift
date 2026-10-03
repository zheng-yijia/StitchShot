import CoreMedia
import Foundation

/// 视频转实况照片的循环模式。
public enum LivePhotoLoopMode: String, CaseIterable, Identifiable {
    /// 直接截取所选片段。
    case trim
    /// 正放 + 倒放折返（仿 Boomerang）。
    case boomerang

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .trim: return "直接截取"
        case .boomerang: return "来回循环"
        }
    }
}

/// 转换参数。
public struct LivePhotoOptions {
    /// 片段起点，会被夹取到素材时长内。
    public var trimStart: CMTime
    /// 片段时长，会被夹取到 ≤ maxDurationSeconds 与剩余时长。
    public var trimDuration: CMTime
    public var loopMode: LivePhotoLoopMode
    /// 封面帧在输出视频时间轴上的位置。
    public var coverTime: CMTime
    /// 输出目录；nil 时自动创建独立临时目录。
    public var outputDirectory: URL?

    public init(
        trimStart: CMTime = .zero,
        trimDuration: CMTime = CMTime(seconds: 3, preferredTimescale: 600),
        loopMode: LivePhotoLoopMode = .trim,
        coverTime: CMTime = .zero,
        outputDirectory: URL? = nil
    ) {
        self.trimStart = trimStart
        self.trimDuration = trimDuration
        self.loopMode = loopMode
        self.coverTime = coverTime
        self.outputDirectory = outputDirectory
    }
}

/// 转换结果：同一 content identifier 关联的一对资源。
public struct LivePhotoResult {
    /// still.jpg（含 Apple Maker Note 17）。
    public let photoURL: URL
    /// video.mov（含 content identifier 与 still-image-time 元数据轨道）。
    public let videoURL: URL
    public let identifier: String
    /// 输出视频时长。
    public let duration: CMTime

    public init(photoURL: URL, videoURL: URL, identifier: String, duration: CMTime) {
        self.photoURL = photoURL
        self.videoURL = videoURL
        self.identifier = identifier
        self.duration = duration
    }
}

/// 转换错误。
public enum LivePhotoError: LocalizedError {
    case noVideoTrack
    case invalidTrimRange
    case assetReadFailed
    case videoWriteFailed(String)
    case coverImageFailed
    case photoWriteFailed

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "所选视频没有视频轨道"
        case .invalidTrimRange:
            return "截取范围无效"
        case .assetReadFailed:
            return "视频读取失败"
        case .videoWriteFailed(let reason):
            return "视频写入失败：\(reason)"
        case .coverImageFailed:
            return "封面帧提取失败"
        case .photoWriteFailed:
            return "封面图写入失败"
        }
    }
}
