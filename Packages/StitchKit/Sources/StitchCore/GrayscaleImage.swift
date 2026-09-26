import UIKit

/// 8-bit 灰度位图，图像匹配的基础输入。StitchEngine 与 ScrollCaptureKit 共用。
public struct GrayscaleImage {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    /// 两行的平均绝对差（0-255）。columnStep 用于抽样加速。
    public func meanAbsoluteDifference(row y: Int, otherRow oy: Int, in other: GrayscaleImage, columnStep: Int) -> Double {
        guard width == other.width, y >= 0, y < height, oy >= 0, oy < other.height else {
            return .infinity
        }
        var sum = 0
        var count = 0
        var x = 0
        let aBase = y * width
        let bBase = oy * other.width
        while x < width {
            sum += abs(Int(pixels[aBase + x]) - Int(other.pixels[bBase + x]))
            count += 1
            x += columnStep
        }
        return count == 0 ? .infinity : Double(sum) / Double(count)
    }

    /// 宽高互换的转置图：横向拼接转化为纵向算法处理。
    public func transposed() -> GrayscaleImage {
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let rowBase = y * width
            for x in 0..<width {
                out[x * height + y] = pixels[rowBase + x]
            }
        }
        return GrayscaleImage(width: height, height: width, pixels: out)
    }
}

extension GrayscaleImage {
    /// 按目标宽度等比缩放的灰度图。
    public init?(image: UIImage, targetWidth: Int) {
        guard let cgImage = image.cgImage, targetWidth > 0 else { return nil }
        self.init(cgImage: cgImage, targetWidth: targetWidth)
    }

    /// 全分辨率灰度图，用于接缝精修。
    public init?(fullResolutionOf image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage, width: cgImage.width, height: cgImage.height)
    }

    /// 从 CGImage 按目标宽度等比缩放。
    public init?(cgImage: CGImage, targetWidth: Int) {
        guard targetWidth > 0 else { return nil }
        let targetHeight = max(1, Int((CGFloat(cgImage.height) * CGFloat(targetWidth) / CGFloat(cgImage.width)).rounded()))
        self.init(cgImage: cgImage, width: targetWidth, height: targetHeight)
    }

    /// 原尺寸灰度图（如条带、裁剪区域）。
    public init?(cgImage: CGImage) {
        self.init(cgImage: cgImage, width: cgImage.width, height: cgImage.height)
    }

    private init?(cgImage: CGImage, width: Int, height: Int) {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let count = width * height
        let pointer = data.bindMemory(to: UInt8.self, capacity: count)
        self.init(width: width, height: height, pixels: Array(UnsafeBufferPointer(start: pointer, count: count)))
    }
}
