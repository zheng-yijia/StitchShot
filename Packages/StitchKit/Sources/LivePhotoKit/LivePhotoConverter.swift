import AVFoundation
import CoreGraphics
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// 视频 → iOS 实况照片（Live Photo）转换器。
///
/// 输出一对资源，归档进相册后即为原生实况照片：
/// - `still.jpg`：封面帧 JPEG + Apple Maker Note `{17: identifier}`
/// - `video.mov`：H.264 视频 + `mdta` content identifier 电影元数据
///   + `mdta/com.apple.quicktime.still-image-time` 元数据轨道
///
/// 说明：为保证确定性与兼容性，视频一律重编码为 H.264（丢音频），
/// 方向由视频轨 `preferredTransform` 保留，不做像素级旋转。
public enum LivePhotoConverter {

    /// 单次导出时长上限（秒）。
    public static let maxDurationSeconds: Double = 5.0

    /// 往返模式的帧数预算（JPEG 中间态控制内存）。
    private static let boomerangFrameBudget = 120
    private static let fallbackFPS: Float = 30

    // MARK: - Public

    /// 将视频文件转换为实况照片资源对。
    public static func convert(videoURL: URL, options: LivePhotoOptions = LivePhotoOptions()) throws -> LivePhotoResult {
        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        return try convert(asset: asset, options: options)
    }

    /// 将 AVAsset（如来自相册的 PHAsset）转换为实况照片资源对。
    public static func convert(asset: AVAsset, options: LivePhotoOptions = LivePhotoOptions()) throws -> LivePhotoResult {
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw LivePhotoError.noVideoTrack
        }
        let assetDuration = asset.duration
        guard assetDuration.isNumeric, assetDuration > .zero else {
            throw LivePhotoError.invalidTrimRange
        }

        let maxDuration = CMTime(seconds: maxDurationSeconds, preferredTimescale: 600)
        let start = minTime(maxTime(.zero, options.trimStart), assetDuration)
        guard start < assetDuration else { throw LivePhotoError.invalidTrimRange }
        let remaining = assetDuration - start

        var duration = options.trimDuration
        if !duration.isNumeric || duration <= .zero {
            duration = minTime(remaining, maxDuration)
        }
        duration = minTime(minTime(duration, maxDuration), remaining)
        guard duration.isNumeric, duration > .zero else { throw LivePhotoError.invalidTrimRange }
        let range = CMTimeRange(start: start, duration: duration)

        let rawFPS = videoTrack.nominalFrameRate
        let fps = Int32((rawFPS > 1 ? rawFPS : fallbackFPS).rounded())
        let estimatedFrames = Int((duration.seconds * Double(fps)).rounded(.up))
        let frameStride = options.loopMode == .boomerang
            ? max(1, Int((Double(estimatedFrames) / Double(boomerangFrameBudget)).rounded(.up)))
            : 1

        let directory = options.outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("StitchShotLivePhoto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appendingPathComponent("video.mov")
        let photoURL = directory.appendingPathComponent("still.jpg")
        let identifier = UUID().uuidString

        let writtenFrames = try writeVideo(
            asset: asset,
            track: videoTrack,
            range: range,
            fps: fps,
            frameStride: frameStride,
            loopMode: options.loopMode,
            coverTime: options.coverTime,
            identifier: identifier,
            outputURL: videoURL
        )
        let outputDuration = CMTime(value: Int64(writtenFrames), timescale: fps)

        let coverTime = minTime(maxTime(.zero, options.coverTime), maxTime(.zero, duration - CMTime(value: 1, timescale: fps)))
        try writeCoverImage(asset: asset, at: start + coverTime, identifier: identifier, outputURL: photoURL)

        return LivePhotoResult(
            photoURL: photoURL,
            videoURL: videoURL,
            identifier: identifier,
            duration: outputDuration
        )
    }

    // MARK: - Video writing

    private static func writeVideo(
        asset: AVAsset,
        track: AVAssetTrack,
        range: CMTimeRange,
        fps: Int32,
        frameStride: Int,
        loopMode: LivePhotoLoopMode,
        coverTime: CMTime,
        identifier: String,
        outputURL: URL
    ) throws -> Int64 {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw LivePhotoError.assetReadFailed
        }
        reader.timeRange = range
        let trackOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { throw LivePhotoError.assetReadFailed }
        reader.add(trackOutput)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        } catch {
            throw LivePhotoError.videoWriteFailed(error.localizedDescription)
        }
        writer.metadata = [contentIdentifierItem(identifier)]

        let naturalSize = track.naturalSize
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings(size: naturalSize))
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = track.preferredTransform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(naturalSize.width),
                kCVPixelBufferHeightKey as String: Int(naturalSize.height)
            ]
        )
        guard writer.canAdd(videoInput) else { throw LivePhotoError.videoWriteFailed("无法添加视频轨道") }
        writer.add(videoInput)

        var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
        if let hint = stillImageTimeFormatDescription() {
            let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: hint)
            if writer.canAdd(metadataInput) {
                writer.add(metadataInput)
                metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
            }
        }

        guard reader.startReading() else { throw LivePhotoError.assetReadFailed }
        guard writer.startWriting() else {
            throw LivePhotoError.videoWriteFailed(writer.error?.localizedDescription ?? "startWriting 失败")
        }
        writer.startSession(atSourceTime: .zero)

        var bufferedJPEGs: [Data] = []
        var sourceIndex = 0
        var outputIndex: Int64 = 0

        while let sample = trackOutput.copyNextSampleBuffer() {
            defer { sourceIndex += 1 }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            if frameStride > 1, sourceIndex % frameStride != 0 { continue }

            try waitUntilReady(videoInput, writer: writer, reader: reader)
            let time = CMTime(value: outputIndex, timescale: fps)
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw LivePhotoError.videoWriteFailed(writer.error?.localizedDescription ?? "帧写入失败")
            }
            if loopMode == .boomerang, bufferedJPEGs.count < boomerangFrameBudget,
               let jpeg = jpegData(from: pixelBuffer) {
                bufferedJPEGs.append(jpeg)
            }
            outputIndex += 1
        }
        guard reader.status != .failed else { throw LivePhotoError.assetReadFailed }

        if loopMode == .boomerang, bufferedJPEGs.count >= 3 {
            for index in stride(from: bufferedJPEGs.count - 2, through: 1, by: -1) {
                guard let pool = adaptor.pixelBufferPool else { break }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
                      let outputBuffer = buffer,
                      let image = decodeJPEG(bufferedJPEGs[index]) else { continue }
                draw(image, into: outputBuffer)
                try waitUntilReady(videoInput, writer: writer, reader: reader)
                let time = CMTime(value: outputIndex, timescale: fps)
                guard adaptor.append(outputBuffer, withPresentationTime: time) else {
                    throw LivePhotoError.videoWriteFailed(writer.error?.localizedDescription ?? "折返帧写入失败")
                }
                outputIndex += 1
            }
        }

        if let metadataAdaptor {
            let frameDuration = CMTime(value: 1, timescale: fps)
            let outputDuration = CMTime(value: outputIndex, timescale: fps)
            let cover = minTime(maxTime(.zero, coverTime), maxTime(.zero, outputDuration - frameDuration))
            let group = AVTimedMetadataGroup(
                items: [stillImageTimeItem()],
                timeRange: CMTimeRange(start: cover, duration: frameDuration)
            )
            _ = metadataAdaptor.append(group)
            metadataAdaptor.assetWriterInput.markAsFinished()
        }

        videoInput.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()
        guard writer.status == .completed else {
            throw LivePhotoError.videoWriteFailed(writer.error?.localizedDescription ?? "收尾失败")
        }
        return outputIndex
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter, reader: AVAssetReader) throws {
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed || writer.status == .cancelled {
                throw LivePhotoError.videoWriteFailed(writer.error?.localizedDescription ?? "写入中断")
            }
            if reader.status == .failed {
                throw LivePhotoError.assetReadFailed
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private static func videoOutputSettings(size: CGSize) -> [String: Any] {
        let pixelCount = Double(size.width * size.height)
        let bitrate = Int(min(max(pixelCount * 6, 3_000_000), 24_000_000))
        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
    }

    // MARK: - Metadata

    private static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = "com.apple.quicktime.content.identifier" as NSString
        item.keySpace = AVMetadataKeySpace(rawValue: "mdta")
        item.value = identifier as NSString
        item.dataType = "com.apple.metadata.datatype.UTF-8"
        return item
    }

    private static func stillImageTimeItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.key = "com.apple.quicktime.still-image-time" as NSString
        item.keySpace = AVMetadataKeySpace(rawValue: "mdta")
        item.value = 0 as NSNumber
        item.dataType = "com.apple.metadata.datatype.int8"
        return item
    }

    private static func stillImageTimeFormatDescription() -> CMMetadataFormatDescription? {
        let specifications: [[String: Any]] = [[
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                "com.apple.metadata.datatype.int8"
        ]]
        var description: CMMetadataFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: specifications as CFArray,
            formatDescriptionOut: &description
        )
        return status == noErr ? description : nil
    }

    // MARK: - Cover image

    private static func writeCoverImage(asset: AVAsset, at time: CMTime, identifier: String, outputURL: URL) throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        let image: CGImage
        do {
            image = try generator.copyCGImage(at: time, actualTime: nil)
        } catch {
            throw LivePhotoError.coverImageFailed
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: ["17": identifier] as CFDictionary
        ]
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw LivePhotoError.photoWriteFailed
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.photoWriteFailed
        }
    }

    // MARK: - Pixel buffer helpers

    private static func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.85) -> Data? {
        guard let image = makeCGImage(from: pixelBuffer) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func decodeJPEG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let context = bitmapContext(for: pixelBuffer) else { return nil }
        return context.makeImage()
    }

    private static func draw(_ image: CGImage, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = bitmapContext(for: pixelBuffer) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
    }

    private static func bitmapContext(for pixelBuffer: CVPixelBuffer) -> CGContext? {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return CGContext(
            data: baseAddress,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    }

    // MARK: - Time helpers

    private static func minTime(_ a: CMTime, _ b: CMTime) -> CMTime {
        CMTimeCompare(a, b) <= 0 ? a : b
    }

    private static func maxTime(_ a: CMTime, _ b: CMTime) -> CMTime {
        CMTimeCompare(a, b) >= 0 ? a : b
    }
}
