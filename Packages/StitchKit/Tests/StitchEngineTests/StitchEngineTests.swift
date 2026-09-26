import XCTest
import UIKit
import StitchCore
@testable import StitchEngine

final class StitchEngineTests: XCTestCase {

    // MARK: - 测试图合成

    /// 生成确定性随机内容的测试图（固定种子可复现）。
    private func contentImage(width: Int, height: Int, seed: UInt64) -> UIImage {
        var state = seed
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            for _ in 0..<(height / 6) {
                let w = Int(next() % UInt64(max(width / 2, 1))) + 16
                let h = Int(next() % 36) + 8
                let x = Int(next() % UInt64(max(width - w, 1)))
                let y = Int(next() % UInt64(max(height - h, 1)))
                UIColor(
                    hue: CGFloat(next() % 360) / 360.0,
                    saturation: 0.7,
                    brightness: 0.85,
                    alpha: 1
                ).setFill()
                UIRectFill(CGRect(x: x, y: y, width: w, height: h))
            }
        }
    }

    private func cropRows(_ image: UIImage, _ rows: Range<Int>) -> UIImage {
        let cgImage = image.cgImage!
        let rect = CGRect(x: 0, y: rows.lowerBound, width: cgImage.width, height: rows.count)
        return UIImage(cgImage: cgImage.cropping(to: rect)!)
    }

    private func cropColumns(_ image: UIImage, _ columns: Range<Int>) -> UIImage {
        let cgImage = image.cgImage!
        let rect = CGRect(x: columns.lowerBound, y: 0, width: columns.count, height: cgImage.height)
        return UIImage(cgImage: cgImage.cropping(to: rect)!)
    }

    // MARK: - 重叠检测

    func testVerticalOverlapDetection() async {
        // 内容 320x1400；A 取 [0,1000)，B 取 [400,1400) → 真实重叠 600px
        let content = contentImage(width: 320, height: 1400, seed: 42)
        let a = cropRows(content, 0..<1000)
        let b = cropRows(content, 400..<1400)

        let seam = await StitchEngine.detectOverlap(from: a, to: b, direction: .vertical)

        XCTAssertEqual(seam.method, .templateMatch)
        XCTAssertEqual(Double(seam.overlap), 600, accuracy: 8, "检测到的重叠应接近真实值 600")
        XCTAssertGreaterThan(seam.confidence, 0.5)
    }

    func testVerticalChainStitch() async {
        // 三张连续滚动截图：每次滚动 400px
        let content = contentImage(width: 320, height: 2200, seed: 7)
        let a = cropRows(content, 0..<1000)
        let b = cropRows(content, 400..<1400)
        let c = cropRows(content, 800..<1800)

        let plan = await StitchEngine.analyze(images: [a, b, c], direction: .vertical)

        XCTAssertEqual(plan.seamCount, 2)
        XCTAssertEqual(plan.canvasSize.height, 1800, accuracy: 16)
        let rendered = plan.render(images: [a, b, c])
        XCTAssertNotNil(rendered)
        XCTAssertEqual(
            Double(rendered?.cgImage?.height ?? 0),
            Double(plan.canvasSize.height),
            accuracy: 1
        )
    }

    func testHorizontalOverlapDetection() async {
        // 内容 1400x320；A 取列 [0,1000)，B 取列 [400,1400) → 重叠 600px
        let content = contentImage(width: 1400, height: 320, seed: 99)
        let a = cropColumns(content, 0..<1000)
        let b = cropColumns(content, 400..<1400)

        let seam = await StitchEngine.detectOverlap(from: a, to: b, direction: .horizontal)

        XCTAssertEqual(seam.method, .templateMatch)
        XCTAssertEqual(Double(seam.overlap), 600, accuracy: 8)
    }

    func testNoOverlapForUnrelatedImages() async {
        let a = contentImage(width: 320, height: 800, seed: 1)
        let b = contentImage(width: 320, height: 800, seed: 123456)

        let seam = await StitchEngine.detectOverlap(from: a, to: b, direction: .vertical)

        XCTAssertEqual(seam.method, .none)
        XCTAssertEqual(seam.overlap, 0)
    }

    // MARK: - StitchPlan

    func testPlanCanvasRecomputeAfterAdjust() {
        var plan = StitchPlan(
            direction: .vertical,
            imageSizes: [CGSize(width: 100, height: 100), CGSize(width: 100, height: 100)],
            seams: [Seam(overlap: 30, confidence: 0.9, method: .templateMatch, maxOverlap: 98)]
        )
        XCTAssertEqual(plan.canvasSize.height, 170, accuracy: 0.1)

        plan.adjustSeam(at: 0, newOverlap: 50)
        XCTAssertEqual(plan.canvasSize.height, 150, accuracy: 0.1)
        XCTAssertTrue(plan.seams[0].userAdjusted)
    }

    func testSeamOverlapClamped() {
        var seam = Seam(overlap: 10, confidence: 1, method: .templateMatch, maxOverlap: 98)
        seam.setOverlap(500, byUser: true)
        XCTAssertEqual(seam.overlap, 98)
        seam.setOverlap(-5, byUser: false)
        XCTAssertEqual(seam.overlap, 0)
    }

    func testProblematicSeamDetection() {
        let plan = StitchPlan(
            direction: .vertical,
            imageSizes: [
                CGSize(width: 100, height: 100),
                CGSize(width: 100, height: 100),
                CGSize(width: 100, height: 100)
            ],
            seams: [
                Seam(overlap: 40, confidence: 0.9, method: .templateMatch, maxOverlap: 98),
                Seam(overlap: 0, confidence: 0, method: .none, maxOverlap: 98)
            ]
        )
        XCTAssertEqual(plan.problematicSeamIndices, [1])
    }

    func testPlacementExcludesOverlap() {
        let plan = StitchPlan(
            direction: .vertical,
            imageSizes: [CGSize(width: 100, height: 200), CGSize(width: 100, height: 200)],
            seams: [Seam(overlap: 50, confidence: 1, method: .templateMatch, maxOverlap: 196)]
        )
        let first = plan.placement(for: 0)
        XCTAssertEqual(first.crop, CGRect(x: 0, y: 0, width: 100, height: 200))

        let second = plan.placement(for: 1)
        XCTAssertEqual(second.crop, CGRect(x: 0, y: 50, width: 100, height: 150))
        XCTAssertEqual(second.origin.y, 200, accuracy: 0.1)
    }
}
