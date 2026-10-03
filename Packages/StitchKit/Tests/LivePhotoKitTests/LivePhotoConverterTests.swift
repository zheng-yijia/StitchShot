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

    /// 生成纯色帧视频（默认 640×360 @30fps）；可选附带静音 AAC 音轨。
    private func makeVideo(
        seconds: Double,
        fps: Int32 = 30,
        size: CGSize = CGSize(width: 640, height: 360),
        withAudio: Bool = false
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

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64000
            ])
            XCTAssertTrue(writer.canAdd(audio))
            writer.add(audio)
            audioInput = audio
        }

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
        if let audioInput {
            try appendSilentAudio(to: audioInput, seconds: seconds)
            audioInput.markAsFinished()
        }
        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    /// 静音 PCM（16-bit mono 44.1kHz）分块喂给 AAC 编码输入。
    private func appendSilentAudio(to input: AVAssetWriterInput, seconds: Double) throws {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw LivePhotoError.videoWriteFailed("无法创建静音音频格式")
        }

        let framesPerChunk = 1024
        let bytesPerChunk = framesPerChunk * 2
        let totalFrames = Int(seconds * 44100)
        var writtenFrames = 0
        while writtenFrames < totalFrames {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            var blockBuffer: CMBlockBuffer?
            let blockStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: bytesPerChunk,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: bytesPerChunk,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
            guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
                throw LivePhotoError.videoWriteFailed("无法创建静音数据块")
            }
            CMBlockBufferFillDataBytes(
                with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: bytesPerChunk
            )

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 44100),
                presentationTimeStamp: CMTime(value: Int64(writtenFrames), timescale: 44100),
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: framesPerChunk,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 1,
                sampleSizeArray: [bytesPerChunk],
                sampleBufferOut: &sampleBuffer
            )
            guard sampleStatus == noErr, let sampleBuffer, input.append(sampleBuffer) else {
                throw LivePhotoError.videoWriteFailed("静音音频写入失败")
            }
            writtenFrames += framesPerChunk
        }
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

    func testTrimPreservesAudioAndRebasesTimeline() throws {
        let source = try makeVideo(seconds: 2.0, withAudio: true)
        var options = LivePhotoOptions()
        options.trimStart = CMTime(seconds: 0.5, preferredTimescale: 600)
        options.trimDuration = CMTime(seconds: 1.5, preferredTimescale: 600)
        options.preservesAudio = true
        options.outputDirectory = tempDir.appendingPathComponent("with-audio-\(UUID().uuidString)", isDirectory: true)

        let result = try LivePhotoConverter.convert(videoURL: source, options: options)

        let output = AVURLAsset(url: result.videoURL)
        let audioTracks = output.tracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        // 源起点 0.5s 被截掉后时间戳平移到零基线
        XCTAssertEqual(audioTrack.timeRange.start.seconds, 0, accuracy: 0.1)
        XCTAssertGreaterThan(audioTrack.timeRange.duration.seconds, 1.0)

        // 关闭选项后输出无音轨
        options.preservesAudio = false
        options.outputDirectory = tempDir.appendingPathComponent("muted-\(UUID().uuidString)", isDirectory: true)
        let muted = try LivePhotoConverter.convert(videoURL: source, options: options)
        XCTAssertTrue(AVURLAsset(url: muted.videoURL).tracks(withMediaType: .audio).isEmpty)
    }

    func testBoomerangDropsAudio() throws {
        let source = try makeVideo(seconds: 1.0, withAudio: true)
        var options = LivePhotoOptions()
        options.loopMode = .boomerang
        options.preservesAudio = true

        let result = try LivePhotoConverter.convert(videoURL: source, options: options)

        let output = AVURLAsset(url: result.videoURL)
        XCTAssertTrue(output.tracks(withMediaType: .audio).isEmpty)
        XCTAssertEqual(output.tracks(withMediaType: .metadata).count, 1)
    }
}
