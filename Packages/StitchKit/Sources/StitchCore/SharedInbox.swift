import Foundation

public struct InboxItem: Codable, Identifiable, Hashable {
    public var id: UUID
    public var fileName: String
    public var source: String
    public var createdAt: Date

    public init(id: UUID = UUID(), fileName: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.fileName = fileName
        self.source = source
        self.createdAt = createdAt
    }

    public var fileURL: URL {
        AppConstants.inboxDirectoryURL.appendingPathComponent(fileName)
    }
}

/// 主 App 与各扩展之间传递图片的共享收件箱（App Group 容器）。
public enum SharedInbox {
    private static let manifestURL = AppConstants.inboxDirectoryURL
        .appendingPathComponent("manifest.json")

    @discardableResult
    public static func saveImage(data: Data, source: String, fileExtension ext: String = "png") throws -> InboxItem {
        let fm = FileManager.default
        try fm.createDirectory(at: AppConstants.inboxDirectoryURL, withIntermediateDirectories: true)
        let item = InboxItem(fileName: "\(UUID().uuidString).\(ext)", source: source)
        try data.write(to: item.fileURL, options: .atomic)
        var items = pendingItems()
        items.append(item)
        try persist(items)
        return item
    }

    public static func pendingItems() -> [InboxItem] {
        guard let data = try? Data(contentsOf: manifestURL),
              let items = try? JSONDecoder().decode([InboxItem].self, from: data) else {
            return []
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    public static func remove(_ item: InboxItem) {
        try? FileManager.default.removeItem(at: item.fileURL)
        let remaining = pendingItems().filter { $0.id != item.id }
        try? persist(remaining)
    }

    public static func removeAll() {
        try? FileManager.default.removeItem(at: AppConstants.inboxDirectoryURL)
    }

    private static func persist(_ items: [InboxItem]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: AppConstants.inboxDirectoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: manifestURL, options: .atomic)
    }
}
