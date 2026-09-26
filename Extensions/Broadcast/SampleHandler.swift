import ReplayKit
import CoreMedia
import StitchCore
import ScrollCaptureKit

/// 滚动截图广播扩展：接收系统录屏帧 → 位移估计 → 条带落盘 → 主 App 合成长图。
class SampleHandler: RPBroadcastSampleHandler {

    private var session: ScrollCaptureSession?
    private var frameCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        session = ScrollCaptureSession()
        ScrollCaptureStatusStore.save(ScrollCaptureStatus(
            state: .recording,
            frameCount: 0,
            resultFileName: session?.sessionID
        ))
    }

    override func broadcastPaused() {
        ScrollCaptureStatusStore.save(ScrollCaptureStatus(
            state: .paused,
            frameCount: frameCount,
            resultFileName: session?.sessionID
        ))
    }

    override func broadcastResumed() {
        ScrollCaptureStatusStore.save(ScrollCaptureStatus(
            state: .recording,
            frameCount: frameCount,
            resultFileName: session?.sessionID
        ))
    }

    override func broadcastFinished() {
        session?.finish(totalFrames: frameCount)
        session = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            frameCount += 1
            session?.processVideoFrame(sampleBuffer, absoluteFrameIndex: frameCount)
        case .audioApp, .audioMic:
            break
        @unknown default:
            break
        }
    }
}
