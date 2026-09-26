import Foundation

public enum StitchDirection: String, Codable, CaseIterable {
    case vertical
    case horizontal

    public var displayName: String {
        switch self {
        case .vertical: return "竖向拼接"
        case .horizontal: return "横向拼接"
        }
    }
}

public struct ScrollCaptureStatus: Codable {
    public enum State: String, Codable {
        case idle
        case recording
        case paused
        case finished
        case failed
    }

    public var state: State
    public var frameCount: Int
    public var updatedAt: Date
    /// 滚动截图会话 ID（对应 App Group 中 ScrollCapture/<id>/ 目录）。
    public var resultFileName: String?
    public var stripCount: Int?
    public var totalHeight: Int?

    public init(
        state: State,
        frameCount: Int = 0,
        updatedAt: Date = Date(),
        resultFileName: String? = nil,
        stripCount: Int? = nil,
        totalHeight: Int? = nil
    ) {
        self.state = state
        self.frameCount = frameCount
        self.updatedAt = updatedAt
        self.resultFileName = resultFileName
        self.stripCount = stripCount
        self.totalHeight = totalHeight
    }
}

public enum ScrollCaptureStatusStore {
    private static let key = "scrollCapture.status"

    public static func save(_ status: ScrollCaptureStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        AppConstants.sharedDefaults.set(data, forKey: key)
    }

    public static func load() -> ScrollCaptureStatus? {
        guard let data = AppConstants.sharedDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScrollCaptureStatus.self, from: data)
    }

    public static func reset() {
        AppConstants.sharedDefaults.removeObject(forKey: key)
    }
}
