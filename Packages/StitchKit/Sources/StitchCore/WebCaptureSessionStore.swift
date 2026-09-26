import Foundation

/// Safari 扩展整页捕获的一次会话：逐屏截取的帧序列。
public struct WebCaptureSession: Codable, Identifiable, Hashable {
    public var id: String
    public var frameFiles: [String]
    public var pageURL: String?
    public var createdAt: Date

    public init(id: String, frameFiles: [String], pageURL: String?, createdAt: Date = Date()) {
        self.id = id
        self.frameFiles = frameFiles
        self.pageURL = pageURL
        self.createdAt = createdAt
    }

    public var directoryURL: URL {
        WebCaptureSessionStore.rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    public var frameURLs: [URL] {
        frameFiles.map { directoryURL.appendingPathComponent($0) }
    }
}

/// Safari 扩展 → 主 App 的整页捕获会话存储（App Group 容器）。
/// 扩展按 begin → frame × N → end 顺序写入；end 落地 manifest 后主 App 才可见。
public enum WebCaptureSessionStore {
    public static var rootDirectory: URL {
        AppConstants.sharedContainerURL.appendingPathComponent("WebCapture", isDirectory: true)
    }

    public static func beginSession(id: String) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory.appendingPathComponent(id, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    public static func saveFrame(id: String, data: Data, index: Int) throws {
        let url = rootDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(String(format: "frame_%04d.png", index))
        try data.write(to: url, options: .atomic)
    }

    /// 写入 manifest；只有 frameCount 与目录内帧数一致才生效。
    @discardableResult
    public static func finishSession(id: String, frameCount: Int, pageURL: String?) throws -> WebCaptureSession {
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        let frameFiles = (0..<frameCount).map { String(format: "frame_%04d.png", $0) }
        for file in frameFiles {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        let session = WebCaptureSession(id: id, frameFiles: frameFiles, pageURL: pageURL)
        let data = try JSONEncoder().encode(session)
        try data.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        return session
    }

    public static func sessions() -> [WebCaptureSession] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("manifest.json")),
                  let session = try? JSONDecoder().decode(WebCaptureSession.self, from: data) else {
                return nil
            }
            return session
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public static func loadFrames(_ session: WebCaptureSession) -> [Data] {
        session.frameURLs.compactMap { try? Data(contentsOf: $0) }
    }

    public static func delete(id: String) {
        try? FileManager.default.removeItem(at: rootDirectory.appendingPathComponent(id, isDirectory: true))
    }

    public static func deleteAll() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
