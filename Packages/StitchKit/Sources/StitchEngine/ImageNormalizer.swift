import UIKit
import StitchCore

enum ImageNormalizer {
    /// 仅处理旋转方向（照片常见）；scale 不影响——全流程在像素坐标系工作。
    static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up, let cgImage = image.cgImage else {
            return image
        }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}

extension UIImage {
    /// 像素尺寸（忽略 scale 与方向）。
    var stitchPixelSize: CGSize {
        guard let cgImage = cgImage else { return .zero }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }
}

extension CGSize {
    func stitchMainLength(direction: StitchDirection) -> CGFloat {
        direction == .vertical ? height : width
    }
}
