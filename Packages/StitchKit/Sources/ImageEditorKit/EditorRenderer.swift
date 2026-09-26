import CoreImage
import UIKit

/// 编辑器渲染管线：基础级 → 核心级 → 完整级。
public enum EditorRenderer {

    // MARK: - Pipeline stages

    /// 基础级：原图 + 状态栏清理（裁剪工具在此层级预览，坐标 = 原图像素）。
    public static func renderBase(_ model: EditModel) -> UIImage {
        guard let clean = model.statusBarClean else { return model.base }
        return applyStatusBarClean(to: model.base, config: clean)
    }

    /// 核心级：基础级 + 裁剪 + 马赛克 + 标注（马赛克/标注工具在此层级预览）。
    public static func renderCore(_ model: EditModel) -> UIImage {
        var image = renderBase(model)
        if let crop = model.cropRect {
            image = cropImage(image, to: crop)
        }
        if !model.mosaicStrokes.isEmpty {
            image = applyMosaic(to: image, strokes: model.mosaicStrokes)
        }
        if !model.annotations.isEmpty {
            image = applyAnnotations(to: image, annotations: model.annotations)
        }
        return image
    }

    /// 完整级：核心级 + 水印 + 边框 + 带壳（导出结果）。
    public static func renderFull(_ model: EditModel) -> UIImage {
        var image = renderCore(model)
        if let watermark = model.watermark, !watermark.text.isEmpty {
            image = applyWatermark(to: image, config: watermark)
        }
        if let border = model.border, border.thicknessFraction > 0 {
            image = applyBorder(to: image, config: border)
        }
        if let shell = model.shell {
            image = DeviceShell.render(screenshot: image, config: shell)
        }
        return image
    }

    // MARK: - Status bar clean

    private static func applyStatusBarClean(to image: UIImage, config: StatusBarCleanConfig) -> UIImage {
        let size = image.size
        guard size.height > 0 else { return image }
        let barHeight = max(1, size.height * config.heightFraction)
        let barRect = CGRect(x: 0, y: 0, width: size.width, height: barHeight)
        let sampleY = min(size.height - 1, barHeight + 2)
        let fillColor = averageColor(of: image, sampleRect: CGRect(x: 0, y: sampleY, width: size.width, height: 1))
            ?? UIColor.white

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            fillColor.setFill()
            ctx.fill(barRect)
            if config.style == .idealized {
                drawIdealizedStatusBar(in: barRect, background: fillColor)
            }
        }
    }

    /// Picsew 风格理想状态栏：9:41 + 满信号/满电，深色或浅色自适应。
    private static func drawIdealizedStatusBar(in rect: CGRect, background: UIColor) {
        var white: CGFloat = 1
        background.getWhite(&white, alpha: nil)
        let fg = white > 0.6 ? UIColor.black : UIColor.white

        let font = UIFont.systemFont(ofSize: rect.height * 0.42, weight: .semibold)
        let time = NSAttributedString(string: "9:41", attributes: [.font: font, .foregroundColor: fg])
        let timeY = rect.midY - time.size().height / 2
        time.draw(at: CGPoint(x: rect.width * 0.075, y: timeY))

        // 电池：外壳 + 满格 + 电极
        let batteryH = rect.height * 0.34
        let batteryW = batteryH * 2.1
        let batteryY = rect.midY - batteryH / 2
        let batteryX = rect.width * 0.925 - batteryW
        fg.setFill()
        let bodyRect = CGRect(x: batteryX, y: batteryY, width: batteryW, height: batteryH)
        let body = UIBezierPath(roundedRect: bodyRect, cornerRadius: batteryH * 0.25)
        fg.setStroke()
        body.lineWidth = max(1, batteryH * 0.1)
        body.stroke()
        UIBezierPath(roundedRect: bodyRect.insetBy(dx: batteryH * 0.16, dy: batteryH * 0.16),
                     cornerRadius: batteryH * 0.12).fill()
        let tip = CGRect(x: batteryX + batteryW + batteryH * 0.08,
                         y: rect.midY - batteryH * 0.18,
                         width: batteryH * 0.1, height: batteryH * 0.36)
        UIBezierPath(roundedRect: tip, cornerRadius: batteryH * 0.05).fill()

        // 信号强度（四根递增柱）
        let barW = rect.height * 0.075
        var sigX = batteryX - rect.width * 0.035 - barW * 4 - barW * 0.6 * 3
        for i in 0..<4 {
            let h = rect.height * (0.16 + 0.07 * CGFloat(i))
            let r = CGRect(x: sigX, y: rect.midY + batteryH / 2 - h, width: barW, height: h)
            UIBezierPath(roundedRect: r, cornerRadius: barW * 0.3).fill()
            sigX += barW * 1.6
        }
    }

    // MARK: - Crop

    private static func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        let clamped = rect.integral.intersection(bounds)
        guard clamped.width >= 2, clamped.height >= 2,
              let cg = image.cgImage?.cropping(to: clamped) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Mosaic

    private static func applyMosaic(to image: UIImage, strokes: [MosaicStroke]) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let size = image.size
        let ciImage = CIImage(cgImage: cg)

        let pixelStrokes = strokes.filter { $0.style == .pixelate }
        let blurStrokes = strokes.filter { $0.style == .blur }
        var result = ciImage

        if !pixelStrokes.isEmpty {
            let mask = strokeMask(strokes: pixelStrokes, size: size)
            let scale = min(32, max(8, size.width / 120))
            if let pix = CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: result,
                kCIInputScaleKey: scale,
                kCIInputCenterKey: CIVector(x: size.width / 2, y: size.height / 2)
            ])?.outputImage?.cropped(to: ciImage.extent) {
                result = blend(base: result, effect: pix, mask: mask)
            }
        }
        if !blurStrokes.isEmpty {
            let mask = strokeMask(strokes: blurStrokes, size: size)
            let blurred = result.clampedToExtent()
                .applyingGaussianBlur(sigma: max(4, size.width / 90))
                .cropped(to: ciImage.extent)
            result = blend(base: result, effect: blurred, mask: mask)
        }

        let context = CIContext()
        guard let out = context.createCGImage(result, from: ciImage.extent) else { return image }
        return UIImage(cgImage: out, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 笔刷掩码：黑底白笔迹（CIImage 坐标，y 向上）。
    private static func strokeMask(strokes: [MosaicStroke], size: CGSize) -> CIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let maskImage = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                guard stroke.points.count > 1 else { continue }
                cg.setLineWidth(max(2, stroke.widthFraction * size.width))
                cg.beginPath()
                for (i, p) in stroke.points.enumerated() {
                    let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
                    if i == 0 { cg.move(to: pt) } else { cg.addLine(to: pt) }
                }
                cg.strokePath()
            }
        }
        guard let maskCG = maskImage.cgImage else { return nil }
        return CIImage(cgImage: maskCG)
    }

    private static func blend(base: CIImage, effect: CIImage, mask: CIImage?) -> CIImage {
        guard let mask,
              let out = CIFilter(name: "CIBlendWithMask", parameters: [
                  kCIInputImageKey: effect,
                  kCIInputBackgroundImageKey: base,
                  kCIInputMaskImageKey: mask
              ])?.outputImage else { return base }
        return out.cropped(to: base.extent)
    }

    // MARK: - Annotations

    private static func applyAnnotations(to image: UIImage, annotations: [AnnotationItem]) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for item in annotations {
                cg.setStrokeColor(item.color.cgColor)
                cg.setFillColor(item.color.cgColor)
                let lineWidth = max(2, item.widthFraction * size.width)
                cg.setLineWidth(lineWidth)
                let pts = item.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                switch item.kind {
                case .freehand:
                    guard pts.count > 1 else { continue }
                    cg.beginPath()
                    for (i, p) in pts.enumerated() {
                        if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
                    }
                    cg.strokePath()
                case .line:
                    guard pts.count >= 2 else { continue }
                    cg.beginPath()
                    cg.move(to: pts[0])
                    cg.addLine(to: pts[1])
                    cg.strokePath()
                case .arrow:
                    guard pts.count >= 2 else { continue }
                    let (start, end) = (pts[0], pts[1])
                    cg.beginPath()
                    cg.move(to: start)
                    cg.addLine(to: end)
                    cg.strokePath()
                    drawArrowHead(from: start, to: end, lineWidth: lineWidth, in: cg)
                case .rectangle:
                    guard pts.count >= 2 else { continue }
                    cg.stroke(rectFrom(pts[0], pts[1]))
                case .ellipse:
                    guard pts.count >= 2 else { continue }
                    cg.strokeEllipse(in: rectFrom(pts[0], pts[1]))
                }
            }
        }
    }

    private static func drawArrowHead(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, in cg: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLen = max(lineWidth * 4, 14)
        let spread: CGFloat = .pi / 7
        for sign: CGFloat in [1, -1] {
            let a = angle + .pi + sign * spread
            cg.beginPath()
            cg.move(to: end)
            cg.addLine(to: CGPoint(x: end.x + headLen * cos(a), y: end.y + headLen * sin(a)))
            cg.strokePath()
        }
    }

    private static func rectFrom(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Watermark

    private static func applyWatermark(to image: UIImage, config: WatermarkConfig) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            let fontSize = max(10, config.sizeFraction * size.width)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: config.color.withAlphaComponent(config.opacity)
            ]
            let textSize = (config.text as NSString).size(withAttributes: attrs)
            let margin = fontSize * 0.6
            let x: CGFloat
            switch config.position {
            case .topLeft, .centerLeft, .bottomLeft: x = margin
            case .topCenter, .center, .bottomCenter: x = (size.width - textSize.width) / 2
            case .topRight, .centerRight, .bottomRight: x = size.width - textSize.width - margin
            }
            let y: CGFloat
            switch config.position {
            case .topLeft, .topCenter, .topRight: y = margin
            case .centerLeft, .center, .centerRight: y = (size.height - textSize.height) / 2
            case .bottomLeft, .bottomCenter, .bottomRight: y = size.height - textSize.height - margin
            }
            (config.text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
        }
    }

    // MARK: - Border

    private static func applyBorder(to image: UIImage, config: BorderConfig) -> UIImage {
        let size = image.size
        let t = max(1, config.thicknessFraction * size.width)
        let canvas = CGSize(width: size.width + t * 2, height: size.height + t * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            config.color.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            image.draw(in: CGRect(x: t, y: t, width: size.width, height: size.height))
        }
    }

    // MARK: - Color sampling

    /// 采样指定像素区域的平均色（缩到 1×1 像素）。
    static func averageColor(of image: UIImage, sampleRect: CGRect) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let clamped = sampleRect.integral.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1,
              let cropped = cg.cropping(to: clamped) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}
