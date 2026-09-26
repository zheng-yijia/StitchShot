import StitchCore

public struct MotionEstimate {
    /// 垂直滚动量（工作尺度像素）。>0 表示向下滚动（内容上移），<0 表示回滚。
    public var delta: Int
    /// 匹配分数（0-255，越小越可信）。
    public var score: Double
}

/// 相邻录屏帧的滚动位移估计：取当前帧中部条带为模板，在上一帧中按候选 delta 匹配。
public struct ScrollMotionEstimator {
    private let acceptThreshold = 14.0

    public init() {}

    public func estimate(previous: GrayscaleImage, current: GrayscaleImage) -> MotionEstimate? {
        guard previous.width == current.width, previous.height == current.height else { return nil }
        let height = current.height
        let t0 = Int(Double(height) * 0.30)
        let templateHeight = max(8, Int(Double(height) * 0.22))
        let minDelta = -Int(Double(height) * 0.08)
        let maxDelta = height - t0 - templateHeight - 2
        guard maxDelta > minDelta else { return nil }

        var bestScore = Double.infinity
        var secondBest = Double.infinity
        var bestDelta = 0

        var delta = minDelta
        while delta <= maxDelta {
            var sum = 0.0
            var rows = 0
            var r = 0
            while r < templateHeight {
                sum += current.meanAbsoluteDifference(
                    row: t0 + r,
                    otherRow: t0 + delta + r,
                    in: previous,
                    columnStep: 2
                )
                rows += 1
                r += 3
            }
            let score = sum / Double(max(rows, 1))
            if score < bestScore {
                secondBest = bestScore
                bestScore = score
                bestDelta = delta
            } else if score < secondBest {
                secondBest = score
            }
            delta += 1
        }

        guard bestScore <= acceptThreshold else { return nil }
        // 歧义保护：大面积纯色区域中最佳与次优几乎无区分时不采纳。
        if secondBest < .infinity, secondBest - bestScore < 1.0, bestScore > 6 {
            return nil
        }
        return MotionEstimate(delta: bestDelta, score: bestScore)
    }
}
