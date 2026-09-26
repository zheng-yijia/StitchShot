import UIKit

/// 程序化带壳截图：不依赖素材图，按截图尺寸绘制设备边框。
public enum DeviceShell {

    public static func render(screenshot: UIImage, config: ShellConfig) -> UIImage {
        let w = screenshot.size.width
        let h = screenshot.size.height
        guard w > 0, h > 0 else { return screenshot }

        let isPad = config.device == .iPad
        let bezel = w * (isPad ? 0.055 : 0.045)
        let margin = w * 0.09

        let bodyRect = CGRect(x: margin, y: margin, width: w + bezel * 2, height: h + bezel * 2)
        let screenRect = bodyRect.insetBy(dx: bezel, dy: bezel)
        let canvas = CGSize(width: bodyRect.width + margin * 2, height: bodyRect.height + margin * 2)

        let bodyRadius = isPad ? w * 0.055 : w * 0.115
        let screenRadius = max(1, bodyRadius - bezel * 0.7)
        let bodyColor = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x14 / 255, alpha: 1)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            config.background.setFill()
            UIRectFill(CGRect(origin: .zero, size: canvas))

            drawSideButtons(bodyRect: bodyRect, bezel: bezel, isPad: isPad, color: bodyColor)

            UIBezierPath(roundedRect: bodyRect, cornerRadius: bodyRadius).addClip()
            bodyColor.setFill()
            UIRectFill(bodyRect)

            let screenPath = UIBezierPath(roundedRect: screenRect, cornerRadius: screenRadius)
            screenPath.addClip()
            screenshot.draw(in: screenRect)

            switch config.device {
            case .iPhoneNotch:
                drawNotch(screenRect: screenRect)
            case .iPhoneDynamicIsland:
                drawDynamicIsland(screenRect: screenRect)
            case .iPad:
                break
            }
        }
    }

    private static func drawNotch(screenRect: CGRect) {
        let w = screenRect.width
        let notchW = w * 0.47
        let notchH = w * 0.085
        let rect = CGRect(x: screenRect.midX - notchW / 2, y: screenRect.minY - 1,
                          width: notchW, height: notchH + 1)
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: [.bottomLeft, .bottomRight],
                                cornerRadii: CGSize(width: notchH * 0.5, height: notchH * 0.5))
        UIColor.black.setFill()
        path.fill()
    }

    private static func drawDynamicIsland(screenRect: CGRect) {
        let w = screenRect.width
        let islandW = w * 0.33
        let islandH = w * 0.082
        let rect = CGRect(x: screenRect.midX - islandW / 2, y: screenRect.minY + w * 0.025,
                          width: islandW, height: islandH)
        UIColor.black.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: islandH / 2).fill()
    }

    private static func drawSideButtons(bodyRect: CGRect, bezel: CGFloat, isPad: Bool, color: UIColor) {
        guard !isPad else { return }
        let btnW = bezel * 0.35
        let btnH = bodyRect.height * 0.09
        color.setFill()
        // 右侧电源键
        let power = CGRect(x: bodyRect.maxX - btnW * 0.15, y: bodyRect.minY + bodyRect.height * 0.22,
                           width: btnW, height: btnH)
        UIBezierPath(roundedRect: power, cornerRadius: btnW / 2).fill()
        // 左侧音量键 ×2
        for i in 0..<2 {
            let v = CGRect(x: bodyRect.minX - btnW * 0.85,
                           y: bodyRect.minY + bodyRect.height * (0.18 + 0.12 * CGFloat(i)),
                           width: btnW, height: btnH)
            UIBezierPath(roundedRect: v, cornerRadius: btnW / 2).fill()
        }
    }
}
