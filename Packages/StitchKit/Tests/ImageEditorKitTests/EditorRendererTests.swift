import UIKit
import XCTest
@testable import ImageEditorKit

final class EditorRendererTests: XCTestCase {

    // MARK: - Helpers

    private func makeImage(width: Int, height: Int, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 顶部蓝条（模拟状态栏）+ 其余红色。
    private func makeStatusBarImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 20))
        }
    }

    /// 左黑右白。
    private func makeSplitImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }
    }

    private func luminance(of image: UIImage, at point: CGPoint) -> CGFloat? {
        EditorRenderer.averageColor(of: image, sampleRect: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
            .flatMap { color in
                var white: CGFloat = 0
                return color.getWhite(&white, alpha: nil) ? white : nil
            }
    }

    // MARK: - Border

    func testBorderExpandsCanvasAndPaintsEdges() {
        var model = EditModel(base: makeImage(width: 100, height: 200, color: .blue))
        model.border = BorderConfig(thicknessFraction: 0.1, color: .red)
        let out = EditorRenderer.renderFull(model)
        XCTAssertEqual(out.size.width, 120, accuracy: 1)
        XCTAssertEqual(out.size.height, 220, accuracy: 1)
        guard let corner = EditorRenderer.averageColor(of: out, sampleRect: CGRect(x: 0, y: 0, width: 4, height: 4)) else {
            XCTFail("无法采样边角")
            return
        }
        var red: CGFloat = 0
        var blue: CGFloat = 0
        XCTAssertTrue(corner.getRed(&red, green: nil, blue: &blue, alpha: nil))
        XCTAssertGreaterThan(red, 0.8)
        XCTAssertLessThan(blue, 0.4)
    }

    // MARK: - Crop

    func testCropTrimsToRect() {
        var model = EditModel(base: makeImage(width: 100, height: 200, color: .white))
        model.cropRect = CGRect(x: 10, y: 20, width: 50, height: 60)
        let out = EditorRenderer.renderCore(model)
        XCTAssertEqual(out.size.width, 50, accuracy: 1)
        XCTAssertEqual(out.size.height, 60, accuracy: 1)
    }

    // MARK: - Status bar

    func testStatusBarSolidFillUsesColorBelowBar() {
        var model = EditModel(base: makeStatusBarImage())
        model.statusBarClean = StatusBarCleanConfig(heightFraction: 0.1, style: .solid)
        let out = EditorRenderer.renderBase(model)
        XCTAssertEqual(out.size.width, 100, accuracy: 1)
        guard let top = EditorRenderer.averageColor(of: out, sampleRect: CGRect(x: 40, y: 4, width: 10, height: 4)) else {
            XCTFail("无法采样状态栏")
            return
        }
        var red: CGFloat = 0
        var blue: CGFloat = 0
        XCTAssertTrue(top.getRed(&red, green: nil, blue: &blue, alpha: nil))
        XCTAssertGreaterThan(red, 0.8)
        XCTAssertLessThan(blue, 0.4)
    }

    // MARK: - Mosaic

    func testMosaicPixelateBlendsBlocksInsideStrokeOnly() {
        var model = EditModel(base: makeSplitImage())
        let stroke = MosaicStroke(
            points: [CGPoint(x: 0.5, y: 0.3), CGPoint(x: 0.5, y: 0.7)],
            widthFraction: 0.3,
            style: .pixelate
        )
        model.mosaicStrokes = [stroke]
        let out = EditorRenderer.renderCore(model)

        // 像素块横跨黑白边界被混合，边界附近应出现中间灰
        var graySamples = 0
        for x in stride(from: 40, through: 60, by: 2) {
            if let l = luminance(of: out, at: CGPoint(x: CGFloat(x), y: 50)), l > 0.2, l < 0.8 {
                graySamples += 1
            }
        }
        XCTAssertGreaterThanOrEqual(graySamples, 2)

        // 笔迹之外保持原样
        XCTAssertEqual(luminance(of: out, at: CGPoint(x: 10, y: 50)) ?? 1, 0, accuracy: 0.05)
        XCTAssertEqual(luminance(of: out, at: CGPoint(x: 90, y: 50)) ?? 0, 1, accuracy: 0.05)
    }

    // MARK: - Watermark

    func testWatermarkKeepsCanvasSize() {
        var model = EditModel(base: makeImage(width: 200, height: 300, color: .gray))
        model.watermark = WatermarkConfig(text: "@test")
        let out = EditorRenderer.renderFull(model)
        XCTAssertEqual(out.size.width, 200, accuracy: 1)
        XCTAssertEqual(out.size.height, 300, accuracy: 1)
    }

    // MARK: - Shell

    func testShellExpandsCanvas() {
        var model = EditModel(base: makeImage(width: 200, height: 400, color: .green))
        model.shell = ShellConfig(device: .iPhoneDynamicIsland, background: .darkGray)
        let out = EditorRenderer.renderFull(model)
        XCTAssertGreaterThan(out.size.width, 200)
        XCTAssertGreaterThan(out.size.height, 400)
    }

    // MARK: - Pipeline order

    func testCropThenBorderUsesCroppedSize() {
        var model = EditModel(base: makeImage(width: 100, height: 200, color: .white))
        model.cropRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        model.border = BorderConfig(thicknessFraction: 0.1, color: .black)
        let out = EditorRenderer.renderFull(model)
        // 边框宽度基于裁剪后宽度：100 * 0.1 = 10
        XCTAssertEqual(out.size.width, 120, accuracy: 1)
        XCTAssertEqual(out.size.height, 120, accuracy: 1)
    }
}
