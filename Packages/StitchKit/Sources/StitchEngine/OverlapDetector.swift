import UIKit
import Vision
import StitchCore

struct OverlapMatch {
    var overlap: Int      // 原图像素
    var score: Double     // 平均绝对差（0-255，越小越可信）
    var method: StitchMethod

    var confidence: Double {
        switch method {
        case .none:
            return 0
        case .templateMatch:
            return max(0.3, min(1, 1 - score / 60))
        case .visionRegistration:
            return max(0.2, min(1, 1 - score / 60))
        }
    }
}

/// 相邻两张图重叠区域的检测器。
/// 主路径：灰度降采样模板匹配 → 全分辨率 ±8px 精修（截图可做到像素级）。
/// 兜底：Vision 平移配准，但用同一 MAD 指标验证后才采纳。
enum OverlapDetector {
    private static let workWidth = 320
    private static let acceptThreshold = 14.0

    static func detect(from first: UIImage, to second: UIImage, direction: StitchDirection) -> OverlapMatch {
        guard var a = GrayscaleImage(image: first, targetWidth: workWidth),
              var b = GrayscaleImage(image: second, targetWidth: workWidth) else {
            return OverlapMatch(overlap: 0, score: .infinity, method: .none)
        }
        if direction == .horizontal {
            a = a.transposed()
            b = b.transposed()
        }

        let fullMainLength = direction == .vertical
            ? (second.cgImage?.height ?? 1)
            : (second.cgImage?.width ?? 1)
        let workToFull = Double(fullMainLength) / Double(b.height)

        if let coarse = templateSearch(a: a, b: b) {
            let estimated = Int((Double(coarse.overlap) * workToFull).rounded())
            let refined = refine(first: first, second: second, direction: direction, estimatedOverlap: estimated)
            return OverlapMatch(overlap: refined.overlap, score: refined.score, method: .templateMatch)
        }

        if let vision = visionRegistration(first: first, second: second, direction: direction) {
            let workOverlap = Int((Double(vision.overlap) / workToFull).rounded())
            if workOverlap > 4 {
                let score = bandScore(a: a, b: b, overlap: workOverlap)
                if score <= acceptThreshold * 1.5 {
                    return OverlapMatch(overlap: vision.overlap, score: score, method: .visionRegistration)
                }
            }
        }

        return OverlapMatch(overlap: 0, score: .infinity, method: .none)
    }

    // MARK: - 模板匹配（粗尺度）

    private struct CoarseMatch {
        var overlap: Int  // 工作尺度像素
        var score: Double
    }

    /// 从第二张图顶部（跳过状态栏）取模板条带，在第一张图下部搜索最佳对齐位置。
    /// 多级模板高度递减，兼顾大重叠与小重叠场景。
    private static func templateSearch(a: GrayscaleImage, b: GrayscaleImage) -> CoarseMatch? {
        let configs: [(skip: Double, template: Double)] = [(0.06, 0.25), (0.06, 0.12), (0.02, 0.06)]
        for (skipFraction, templateFraction) in configs {
            let t0 = Int((Double(b.height) * skipFraction).rounded())
            let templateHeight = Int((Double(b.height) * templateFraction).rounded())
            guard templateHeight >= 8,
                  t0 + templateHeight < b.height,
                  a.height > t0 + templateHeight + 4 else { continue }

            let yMin = t0 + 2
            let yMax = a.height - templateHeight
            guard yMax > yMin else { continue }

            var bestScore = Double.infinity
            var bestY = yMin
            var y = yMin
            while y <= yMax {
                var sum = 0.0
                var rowsCounted = 0
                var aborted = false
                var r = 0
                while r < templateHeight {
                    sum += a.meanAbsoluteDifference(row: y + r, otherRow: t0 + r, in: b, columnStep: 2)
                    rowsCounted += 1
                    if rowsCounted % 16 == 0, sum / Double(rowsCounted) > bestScore * 1.3 {
                        aborted = true
                        break
                    }
                    r += 2
                }
                if !aborted {
                    let score = sum / Double(rowsCounted)
                    if score < bestScore {
                        bestScore = score
                        bestY = y
                    }
                }
                y += 1
            }

            if bestScore <= acceptThreshold {
                return CoarseMatch(overlap: t0 + (a.height - bestY), score: bestScore)
            }
        }
        return nil
    }

    // MARK: - 全分辨率精修

    private static func refine(first: UIImage, second: UIImage, direction: StitchDirection, estimatedOverlap: Int) -> (overlap: Int, score: Double) {
        guard var fa = GrayscaleImage(fullResolutionOf: first),
              var fb = GrayscaleImage(fullResolutionOf: second) else {
            return (estimatedOverlap, 0)
        }
        if direction == .horizontal {
            fa = fa.transposed()
            fb = fb.transposed()
        }

        var best = (overlap: estimatedOverlap, score: Double.infinity)
        for delta in -8...8 {
            let candidate = estimatedOverlap + delta
            guard candidate > 4, candidate < min(fa.height, fb.height) - 2 else { continue }
            let score = bandScore(a: fa, b: fb, overlap: candidate)
            if score < best.score {
                best = (candidate, score)
            }
        }
        return best.score == .infinity ? (estimatedOverlap, 0) : best
    }

    /// 验证候选重叠量：比较重叠区中部条带（A 底部 vs B 顶部）的平均绝对差。
    private static func bandScore(a: GrayscaleImage, b: GrayscaleImage, overlap: Int) -> Double {
        guard overlap > 4, overlap <= a.height, overlap <= b.height else { return .infinity }
        let bandTop = overlap / 3
        var bandHeight = min(60, overlap - bandTop - 1)
        if bandHeight < 8 { bandHeight = min(overlap, 8) }
        guard bandHeight > 0 else { return .infinity }

        var sum = 0.0
        var counted = 0
        var r = 0
        while r < bandHeight {
            let score = a.meanAbsoluteDifference(
                row: a.height - overlap + bandTop + r,
                otherRow: bandTop + r,
                in: b,
                columnStep: 2
            )
            if score == .infinity { return .infinity }
            sum += score
            counted += 1
            r += 2
        }
        return counted == 0 ? .infinity : sum / Double(counted)
    }

    // MARK: - Vision 兜底

    private static func visionRegistration(first: UIImage, second: UIImage, direction: StitchDirection) -> OverlapMatch? {
        guard let cgA = first.cgImage, let cgB = second.cgImage else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: cgB, options: [:])
        let handler = VNImageRequestHandler(cgImage: cgA, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return nil
        }

        let transform = observation.alignmentTransform
        let mainLength = direction == .vertical ? CGFloat(cgA.height) : CGFloat(cgA.width)
        let mainShift = direction == .vertical ? abs(transform.ty) : abs(transform.tx)
        let crossShift = direction == .vertical ? abs(transform.tx) : abs(transform.ty)

        // 合理性：主方向位移在 (0, 全长) 内，交叉方向近乎无位移。
        guard mainShift > 2, mainShift < mainLength, crossShift < mainLength * 0.1 else { return nil }

        // 平移量 = 滚动距离，重叠 = 全长 - 滚动距离（与坐标方向约定无关，取绝对值即可）。
        let overlap = Int(mainLength - mainShift)
        guard overlap > 0 else { return nil }
        return OverlapMatch(overlap: overlap, score: 25, method: .visionRegistration)
    }
}
