import UIKit
import StitchCore

/// 主 App 侧：把扩展落盘的条带序列合成为最终长图。
public enum ScrollCaptureComposer {

    public static func sessionExists(id: String) -> Bool {
        ScrollCaptureSessionStore.loadManifest(id: id) != nil
    }

    /// 按清单顺接合成（条带在扩展侧已像素级对齐，无需再做重叠检测）。
    public static func compose(sessionID: String) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let manifest = ScrollCaptureSessionStore.loadManifest(id: sessionID),
                  !manifest.strips.isEmpty,
                  manifest.imageWidth > 0 else { return nil }

            let directory = ScrollCaptureSessionStore.sessionDirectory(id: sessionID)
            let canvasSize = CGSize(width: manifest.imageWidth, height: manifest.totalHeight)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true

            return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: canvasSize))
                var y: CGFloat = 0
                for strip in manifest.strips {
                    autoreleasepool {
                        let url = directory.appendingPathComponent(strip.file)
                        if let data = try? Data(contentsOf: url),
                           let image = UIImage(data: data),
                           let cgImage = image.cgImage {
                            context.cgContext.draw(
                                cgImage,
                                in: CGRect(x: 0, y: y, width: canvasSize.width, height: CGFloat(strip.height))
                            )
                        }
                    }
                    y += CGFloat(strip.height)
                }
            }
        }.value
    }

    public static func deleteSession(id: String) {
        ScrollCaptureSessionStore.deleteSession(id: id)
    }
}
