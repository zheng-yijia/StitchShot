import ImageEditorKit
import StitchCore
import StitchEngine
import UIKit

/// 拼接自动化核心管线：供 URL Scheme 与 App Intents 共用。
enum StitchAutomation {

    /// clean_status 逐张作用于源图（拼接前去状态栏），mockup 作用于最终结果（Pro 权益）。
    static func stitch(
        images: [UIImage],
        direction: StitchDirection,
        cleanStatus: Bool,
        mockup: Bool
    ) async -> UIImage? {
        var sources = images
        if cleanStatus {
            sources = sources.map(cleanStatusBar(_:))
        }
        let plan = await StitchEngine.analyze(images: sources, direction: direction)
        guard var result = await StitchEngine.render(plan: plan, images: sources) else { return nil }
        let allowMockup = await MainActor.run { mockup && ProUpgradeManager.shared.isPro }
        if allowMockup {
            result = applyMockup(result)
        }
        return result
    }

    static func cleanStatusBar(_ image: UIImage) -> UIImage {
        var model = EditModel(base: image)
        model.statusBarClean = StatusBarCleanConfig()
        return EditorRenderer.renderBase(model)
    }

    static func applyMockup(_ image: UIImage) -> UIImage {
        var model = EditModel(base: image)
        model.shell = ShellConfig()
        return EditorRenderer.renderFull(model)
    }
}
