import UIKit
import StitchCore

public enum StitchMethod: String, Codable {
    case templateMatch
    case visionRegistration
    case none
}

/// 相邻两张图之间的接缝。overlap 为重叠像素数（原图分辨率）。
public struct Seam {
    public private(set) var overlap: Int
    public private(set) var confidence: Double
    public let method: StitchMethod
    public let maxOverlap: Int
    public private(set) var userAdjusted: Bool

    public init(overlap: Int, confidence: Double, method: StitchMethod, maxOverlap: Int) {
        self.overlap = min(max(overlap, 0), maxOverlap)
        self.confidence = confidence
        self.method = method
        self.maxOverlap = maxOverlap
        self.userAdjusted = false
    }

    mutating func setOverlap(_ newValue: Int, byUser: Bool) {
        overlap = min(max(newValue, 0), maxOverlap)
        if byUser {
            userAdjusted = true
            confidence = 1
        }
    }
}

/// 一次拼接的完整布局：每张图的裁剪区域与画布原点，可手动调整后重新渲染。
public struct StitchPlan {
    public let direction: StitchDirection
    public let imageSizes: [CGSize]     // 像素尺寸（与传入图片一一对应）
    public private(set) var seams: [Seam]
    public private(set) var canvasSize: CGSize

    public init(direction: StitchDirection, imageSizes: [CGSize], seams: [Seam]) {
        self.direction = direction
        self.imageSizes = imageSizes
        self.seams = seams
        self.canvasSize = .zero
        recomputeCanvas()
    }

    public var seamCount: Int { seams.count }

    /// 自动检测失败或低置信的接缝，UI 应提示用户手动调整。
    public var problematicSeamIndices: [Int] {
        seams.indices.filter { seams[$0].method == .none || seams[$0].confidence < 0.4 }
    }

    public mutating func adjustSeam(at index: Int, newOverlap: Int) {
        guard seams.indices.contains(index) else { return }
        seams[index].setOverlap(newOverlap, byUser: true)
        recomputeCanvas()
    }

    public mutating func replaceSeam(at index: Int, with seam: Seam) {
        guard seams.indices.contains(index) else { return }
        seams[index] = seam
        recomputeCanvas()
    }

    private mutating func recomputeCanvas() {
        guard let first = imageSizes.first else {
            canvasSize = .zero
            return
        }
        switch direction {
        case .vertical:
            let width = imageSizes.map(\.width).max() ?? first.width
            var height = first.height
            for (index, seam) in seams.enumerated() where imageSizes.indices.contains(index + 1) {
                height += imageSizes[index + 1].height - CGFloat(seam.overlap)
            }
            canvasSize = CGSize(width: width, height: max(height, 1))
        case .horizontal:
            let height = imageSizes.map(\.height).max() ?? first.height
            var width = first.width
            for (index, seam) in seams.enumerated() where imageSizes.indices.contains(index + 1) {
                width += imageSizes[index + 1].width - CGFloat(seam.overlap)
            }
            canvasSize = CGSize(width: max(width, 1), height: height)
        }
    }

    /// 第 index 张图的绘制信息：crop 为原图像素坐标中的保留区域，origin 为画布上的绘制起点。
    public func placement(for index: Int) -> (crop: CGRect, origin: CGPoint) {
        let size = imageSizes[index]
        let crossOffset: CGFloat
        switch direction {
        case .vertical: crossOffset = (canvasSize.width - size.width) / 2
        case .horizontal: crossOffset = (canvasSize.height - size.height) / 2
        }

        if index == 0 {
            switch direction {
            case .vertical: return (CGRect(origin: .zero, size: size), CGPoint(x: crossOffset, y: 0))
            case .horizontal: return (CGRect(origin: .zero, size: size), CGPoint(x: 0, y: crossOffset))
            }
        }

        let seam = seams[index - 1]
        let mainOffset = mainCursor(before: index)
        switch direction {
        case .vertical:
            let crop = CGRect(x: 0, y: seam.overlap, width: Int(size.width), height: Int(size.height) - seam.overlap)
            return (crop, CGPoint(x: crossOffset, y: mainOffset))
        case .horizontal:
            let crop = CGRect(x: seam.overlap, y: 0, width: Int(size.width) - seam.overlap, height: Int(size.height))
            return (crop, CGPoint(x: mainOffset, y: crossOffset))
        }
    }

    /// 第 index 张图新内容沿主轴的画布位置。
    private func mainCursor(before index: Int) -> CGFloat {
        var cursor: CGFloat = 0
        for i in 0..<index {
            let length = imageSizes[i].stitchMainLength(direction: direction)
            cursor += i == 0 ? length : length - CGFloat(seams[i - 1].overlap)
        }
        return cursor
    }

    /// 按当前布局渲染长图。输出 scale 为 1（1 单位 = 1 像素），保证像素级无缝。
    public func render(images: [UIImage]) -> UIImage? {
        guard images.count == imageSizes.count, !images.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            for (index, image) in images.enumerated() {
                guard let cgImage = image.cgImage else { continue }
                let placement = placement(for: index)
                guard !placement.crop.isEmpty,
                      let cropped = cgImage.cropping(to: placement.crop) else { continue }
                context.cgContext.draw(cropped, in: CGRect(origin: placement.origin, size: placement.crop.size))
            }
        }
    }
}
