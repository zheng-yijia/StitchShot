import AVFoundation
import CoreGraphics
import ImageIO
import XCTest
@testable import LivePhotoKit

final class LivePhotoConverterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LivePhotoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Fixtures

    /// 生成纯色帧视频（默认 640×360 @30fps）。
    private func makeVideo(
        seconds: Double,
        fps: Int32 = 30,
        size: CGSize = CGSize(width: 640, height: 360)
    ) throws -> URL {
        let url = tempDir.appendingPathComponent("source-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(seconds * Double(fps))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            guard let pool = adaptor.pixelBufferPool else {
                XCTFail("缺少像素缓冲池")
                throw LivePhotoError.videoWriteFailed("no pixel buffer pool")
            }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer), kCVReturnSuccess)
            guard let pixelBuffer = buffer else {
                throw LivePhotoError.videoWriteFailed("no pixel buffer")
            }
            fill(pixelBuffer: pixelBuffer, level: CGFloat(frame % 10) / 10)
            XCTAssertTrue(adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: Int64(frame), timescale: fps)
            ))
        }
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    /// 以灰度渐变填帧，保证每帧内容可区分。
    private func fill(pixelBuffer: CVPixelBuffer, level: CGFloat) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            XCTFail("无法创建位图上下文")
            return
        }
        context.setFillColor(red: level, green: level, blue: level, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }

    // MARK: - Tests

    func testConvertTrimProducesLivePhotoPair() throws {
        let source = try makeVideo(seconds: 2.0)
        var options = LivePhotoOptions()
        options.trimDuration = CMTime(seconds: 5, preferredTimescale: 600)

        let result = try LivePhotoConverter.convert(videoURL: source, options: options)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.photoURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.videoURL.path))
        XCTAssertEqual(result.photoURL.pathExtension, "jpg")
        XCTAssertEqual(result.videoURL.pathExtension, "mov")
        XCTAssertFalse(result.identifier.isEmpty)

        let photoData = try Data(contentsOf: result.photoURL)
        XCTAssertGreaterThan(photoData.count, 100)
        XCTAssertEqual(photoData.prefix(2), Data([0xFF, 0xD8]))

        guard let photoSource = CGImageSourceCreateWithURL(result.photoURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(photoSource, 0, nil) as? [CFString: Any],
              let makerNote = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] else {
            XCTFail("封面缺少 Apple Maker Note")
            return
        }
        XCTAssertEqual(makerNote["17"] as? String, result.identifier)

        let output = AVURLAsset(url: result.videoURL)
        let contentItems = output.metadata.filter {
            ($0.key as? String) == "com.apple.quicktime.content.identifier"
        }
        XCTAssertEqual(contentItems.count, 1)
        XCTAssertEqual(contentItems.first?.value as? String, result.identifier)

        let metadataTracks = output.tracks(withMediaType: .metadata)
        XCTAssertEqual(metadataTracks.count, 1)

        XCTAssertEqual(result.duration.seconds, 2.0, accuracy: 0.2)
    }

    func testBoomerangGrowsDuration() throws {
        let source = try makeVideo(seconds: 1.0)
        var options = LivePhotoOptions()
        options.loopMode = .boomerang
        options.trimDuration = CMTime(seconds: 5, preferredTimescale: 600)

        let result = try LivePhotoConverter.convert(videoURL: source, options: options)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.videoURL.path))
        // 30 帧正放 + 28 帧折返 ≈ 1.93s
        XCTAssertGreaterThan(result.duration.seconds, 1.6)
        XCTAssertLessThan(result.duration.seconds, 2.2)
    }

    func testClampsToMaxDuration() throws {
        let source = try makeVideo(seconds: 6.0)
        var options = LivePhotoOptions()
        options.trimDuration = CMTime(seconds: 10, preferredTimescale: 600)

        let result = try LivePhotoConverter.convert(videoURL: source, options: options)

        XCTAssertEqual(result.duration.seconds, LivePhotoConverter.maxDurationSeconds, accuracy: 0.25)
    }

    func testInvalidStartThrows() throws {
        let source = try makeVideo(seconds: 1.0)
        var options = LivePhotoOptions()
        options.trimStart = CMTime(seconds: 3, preferredTimescale: 600)

        XCTAssertThrowsError(try LivePhotoConverter.convert(videoURL: source, options: options)) { error in
            guard let liveError = error as? LivePhotoError, case .invalidTrimRange = liveError else {
                XCTFail("错误类型不符：\(error)")
                return
            }
        }
    }
}
