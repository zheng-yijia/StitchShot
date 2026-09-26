import UIKit
import StitchCore

/// 拼接引擎外观：自动重叠检测 → StitchPlan → 渲染。
public enum StitchEngine {

    /// 分析图片序列，生成可调整的拼接布局。
    public static func analyze(images: [UIImage], direction: StitchDirection) async -> StitchPlan {
        let normalized = images.map(ImageNormalizer.normalized)
        return await Task.detached(priority: .userInitiated) {
            analyzeSync(images: normalized, direction: direction)
        }.value
    }

    /// 单对图片的重叠检测，供"重新检测本接缝"使用。
    public static func detectOverlap(from first: UIImage, to second: UIImage, direction: StitchDirection) async -> Seam {
        let a = ImageNormalizer.normalized(first)
        let b = ImageNormalizer.normalized(second)
        return await Task.detached(priority: .userInitiated) {
            let match = OverlapDetector.detect(from: a, to: b, direction: direction)
            return Seam(
                overlap: match.overlap,
                confidence: match.confidence,
                method: match.method,
                maxOverlap: maxOverlap(between: a, and: b, direction: direction)
            )
        }.value
    }

    /// 一步到位：分析并渲染长图。
    public static func stitch(images: [UIImage], direction: StitchDirection) async -> UIImage? {
        let normalized = images.map(ImageNormalizer.normalized)
        let plan = await analyze(images: normalized, direction: direction)
        return await render(plan: plan, images: normalized)
    }

    /// 后台渲染，避免阻塞主线程。
    public static func render(plan: StitchPlan, images: [UIImage]) async -> UIImage? {
        let normalized = images.map(ImageNormalizer.normalized)
        return await Task.detached(priority: .userInitiated) {
            plan.render(images: normalized)
        }.value
    }

    static func analyzeSync(images: [UIImage], direction: StitchDirection) -> StitchPlan {
        let sizes = images.map(\.stitchPixelSize)
        var seams: [Seam] = []
        if images.count > 1 {
            for index in 0..<(images.count - 1) {
                let match = OverlapDetector.detect(from: images[index], to: images[index + 1], direction: direction)
                seams.append(Seam(
                    overlap: match.overlap,
                    confidence: match.confidence,
                    method: match.method,
                    maxOverlap: maxOverlap(between: images[index], and: images[index + 1], direction: direction)
                ))
            }
        }
        return StitchPlan(direction: direction, imageSizes: sizes, seams: seams)
    }

    private static func maxOverlap(between first: UIImage, and second: UIImage, direction: StitchDirection) -> Int {
        let a = first.stitchPixelSize.stitchMainLength(direction: direction)
        let b = second.stitchPixelSize.stitchMainLength(direction: direction)
        return Int(min(a, b) * 0.98)
    }
}
