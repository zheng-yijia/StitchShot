import Foundation

public struct ScrollCaptureStrip: Codable {
    public var file: String
    public var height: Int

    public init(file: String, height: Int) {
        self.file = file
        self.height = height
    }
}

/// 一次滚动截图会话的清单：条带序列即最终长图（扩展侧已对齐，主 App 直接顺接合成）。
public struct ScrollCaptureSessionManifest: Codable {
    public var sessionID: String
    public var state: ScrollCaptureStatus.State
    public var imageWidth: Int
    public var frameCount: Int
    public var strips: [ScrollCaptureStrip]
    public var warnings: [String]
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        sessionID: String,
        state: ScrollCaptureStatus.State,
        imageWidth: Int,
        frameCount: Int,
        strips: [ScrollCaptureStrip],
        warnings: [String],
        startedAt: Date,
        updatedAt: Date
    ) {
        self.sessionID = sessionID
        self.state = state
        self.imageWidth = imageWidth
        self.frameCount = frameCount
        self.strips = strips
        self.warnings = warnings
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var totalHeight: Int {
        strips.reduce(0) { $0 + $1.height }
    }
}

/// 滚动截图会话目录管理（App Group 容器内 ScrollCapture/<id>/）。
public enum ScrollCaptureSessionStore {
    public static var rootDirectory: URL {
        AppConstants.sharedContainerURL.appendingPathComponent("ScrollCapture", isDirectory: true)
    }

    public static func sessionDirectory(id: String) -> URL {
        rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public static func createSession(id: String) throws -> URL {
        let directory = sessionDirectory(id: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func manifestURL(id: String) -> URL {
        sessionDirectory(id: id).appendingPathComponent("manifest.json")
    }

    public static func loadManifest(id: String) -> ScrollCaptureSessionManifest? {
        guard let data = try? Data(contentsOf: manifestURL(id: id)) else { return nil }
        return try? JSONDecoder().decode(ScrollCaptureSessionManifest.self, from: data)
    }

    public static func saveManifest(_ manifest: ScrollCaptureSessionManifest, in directory: URL) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
    }

    public static func deleteSession(id: String) {
        try? FileManager.default.removeItem(at: sessionDirectory(id: id))
    }

    /// 清理历史遗留会话（如异常退出的录制）。
    public static func deleteAllSessions() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
