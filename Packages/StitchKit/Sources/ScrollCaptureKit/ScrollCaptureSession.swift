import UIKit
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import StitchCore

/// 滚动截图会话（Broadcast 扩展侧，内存受限环境）：
/// 不累积长图，仅做帧间位移估计，把"新内容条带"逐条 PNG 落盘，
/// 主 App 之后按清单顺接合成。峰值内存 ≈ 单帧全分辨率（约 15MB）。
public final class ScrollCaptureSession {
    public private(set) var sessionID: String

    private let directory: URL
    private var manifest: ScrollCaptureSessionManifest
    private let estimator = ScrollMotionEstimator()
    private let ciContext = CIContext(options: nil)

    private let workWidth = 256
    private let processEveryNthFrame = 4
    private var scaleFactor = 1.0

    private var previousGray: GrayscaleImage?
    private var latestPixelBuffer: CVPixelBuffer?
    private var pendingWorkDelta = 0
    private var lastTailBand: GrayscaleImage?
    private var stripIndex = 0
    private var consecutiveFailures = 0
    private var didWarnSizeChange = false

    /// 累计位移达到该值（全分辨率像素）才发射一次条带，减少 IO 与编码次数。
    private let emitThresholdFullPx = 48
    private let tailBandHeight = 96
    private let refineBandHeight = 32
    private let acceptThreshold = 14.0

    public init?() {
        let id = UUID().uuidString
        do {
            directory = try ScrollCaptureSessionStore.createSession(id: id)
        } catch {
            return nil
        }
        sessionID = id
        manifest = ScrollCaptureSessionManifest(
            sessionID: id,
            state: .recording,
            imageWidth: 0,
            frameCount: 0,
            strips: [],
            warnings: [],
            startedAt: Date(),
            updatedAt: Date()
        )
        try? ScrollCaptureSessionStore.saveManifest(manifest, in: directory)
    }

    // MARK: - 帧处理

    public func processVideoFrame(_ sampleBuffer: CMSampleBuffer, absoluteFrameIndex: Int) {
        guard absoluteFrameIndex % processEveryNthFrame == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool { process(pixelBuffer) }
        manifest.frameCount = absoluteFrameIndex
    }

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard let frame = makeCGImage(from: pixelBuffer),
              let gray = GrayscaleImage(cgImage: frame, targetWidth: workWidth) else { return }

        if manifest.imageWidth == 0 {
            manifest.imageWidth = frame.width
            scaleFactor = Double(frame.width) / Double(gray.width)
        } else if frame.width != manifest.imageWidth {
            // 录制中途旋转屏幕：跳过该帧，避免拼出错位图。
            if !didWarnSizeChange {
                didWarnSizeChange = true
                addWarning("录制中屏幕方向发生变化，部分帧已跳过")
            }
            return
        }

        guard let previous = previousGray else {
            writeStrip(frame, height: frame.height)
            lastTailBand = tailBand(of: frame)
            previousGray = gray
            latestPixelBuffer = pixelBuffer
            return
        }

        if let estimate = estimator.estimate(previous: previous, current: gray) {
            consecutiveFailures = 0
            pendingWorkDelta += estimate.delta
            let pendingFull = Int((Double(pendingWorkDelta) * scaleFactor).rounded())
            if pendingFull >= emitThresholdFullPx {
                emitStrip(frame: frame, estimatedPending: pendingFull)
                pendingWorkDelta = 0
            }
        } else {
            consecutiveFailures += 1
            if consecutiveFailures == 12 {
                addWarning("部分帧对齐失败已跳过，建议放慢滚动速度")
            }
        }

        previousGray = gray
        latestPixelBuffer = pixelBuffer
    }

    // MARK: - 结束

    /// 广播结束时调用：flush 末尾不足一个发射阈值的增量，写入最终状态。
    public func finish(totalFrames: Int) {
        manifest.frameCount = totalFrames
        let pendingFull = Int((Double(pendingWorkDelta) * scaleFactor).rounded())
        if pendingFull >= 8,
           let buffer = latestPixelBuffer,
           let frame = makeCGImage(from: buffer) {
            emitStrip(frame: frame, estimatedPending: pendingFull)
        }
        latestPixelBuffer = nil
        previousGray = nil

        manifest.state = manifest.strips.isEmpty ? .failed : .finished
        manifest.updatedAt = Date()
        try? ScrollCaptureSessionStore.saveManifest(manifest, in: directory)
        persistStatus(state: manifest.state, totalFrames: totalFrames)
    }

    /// 用户取消或扩展异常终止：删除会话目录。
    public func discard() {
        ScrollCaptureSessionStore.deleteSession(id: sessionID)
    }

    // MARK: - 条带发射

    private func emitStrip(frame: CGImage, estimatedPending: Int) {
        let height = frame.height
        var pending = min(estimatedPending, height - 1)
        if let refined = refinedPending(frame: frame, estimated: pending) {
            pending = refined
        }
        guard pending >= 8,
              let strip = frame.cropping(to: CGRect(x: 0, y: height - pending, width: frame.width, height: pending)) else {
            return
        }
        writeStrip(strip, height: pending)
        lastTailBand = tailBand(of: frame)
    }

    /// 全分辨率精修：在上次发射帧的底部条带中，验证当前帧 strip 顶边界的精确位置。
    private func refinedPending(frame: CGImage, estimated: Int) -> Int? {
        guard let tail = lastTailBand, tail.height >= refineBandHeight else { return nil }
        let height = frame.height
        let band = refineBandHeight
        let maxShift = Int((2 * scaleFactor).rounded()) + 2
        let pMin = max(8, estimated - maxShift)
        let pMax = min(height - band - 1, estimated + maxShift)
        guard pMax > pMin else { return nil }

        guard let region = frame.cropping(to: CGRect(
            x: 0, y: height - pMax - band, width: frame.width, height: (pMax - pMin) + band
        )), let regionGray = GrayscaleImage(cgImage: region) else { return nil }

        var bestScore = Double.infinity
        var bestPending = estimated
        var pending = pMin
        while pending <= pMax {
            var sum = 0.0
            var rows = 0
            var r = 0
            while r < band {
                sum += regionGray.meanAbsoluteDifference(
                    row: (pMax - pending) + r,
                    otherRow: tail.height - band + r,
                    in: tail,
                    columnStep: 2
                )
                rows += 1
                r += 2
            }
            let score = sum / Double(max(rows, 1))
            if score < bestScore {
                bestScore = score
                bestPending = pending
            }
            pending += 1
        }
        return bestScore <= acceptThreshold ? bestPending : nil
    }

    private func writeStrip(_ image: CGImage, height: Int) {
        stripIndex += 1
        let name = String(format: "strip_%06d.png", stripIndex)
        let url = directory.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            addWarning("无法创建图片写入器")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            addWarning("条带写入失败")
            return
        }

        manifest.strips.append(ScrollCaptureStrip(file: name, height: height))
        manifest.updatedAt = Date()
        try? ScrollCaptureSessionStore.saveManifest(manifest, in: directory)
        persistStatus(state: .recording, totalFrames: manifest.frameCount)
    }

    private func tailBand(of frame: CGImage) -> GrayscaleImage? {
        let height = min(tailBandHeight, frame.height)
        guard let crop = frame.cropping(to: CGRect(
            x: 0, y: frame.height - height, width: frame.width, height: height
        )) else { return nil }
        return GrayscaleImage(cgImage: crop)
    }

    // MARK: - 工具

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func addWarning(_ message: String) {
        guard !manifest.warnings.contains(message), manifest.warnings.count < 5 else { return }
        manifest.warnings.append(message)
    }

    private func persistStatus(state: ScrollCaptureStatus.State, totalFrames: Int) {
        ScrollCaptureStatusStore.save(ScrollCaptureStatus(
            state: state,
            frameCount: totalFrames,
            resultFileName: sessionID,
            stripCount: manifest.strips.count,
            totalHeight: manifest.totalHeight
        ))
    }
}
