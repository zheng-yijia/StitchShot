import SafariServices
import StitchCore

/// Safari 网页快照扩展原生端。
/// 支持整页捕获会话（begin → frame × N → end，写入 App Group 供主 App 拼接）
/// 与单张可见区域捕获（存入共享收件箱）。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let type = message["type"] as? String else {
            respond(context, ["ok": false])
            return
        }

        switch type {
        case "capture":
            handleSingleCapture(context, message)
        case "begin":
            handleBegin(context, message)
        case "frame":
            handleFrame(context, message)
        case "end":
            handleEnd(context, message)
        default:
            respond(context, ["ok": false])
        }
    }

    /// 单张可见区域 → 共享收件箱。
    private func handleSingleCapture(_ context: NSExtensionContext, _ message: [String: Any]) {
        var saved = false
        if let base64 = message["imageData"] as? String,
           let data = Data(base64Encoded: base64) {
            saved = (try? SharedInbox.saveImage(data: data, source: "safari")) != nil
        }
        respond(context, ["ok": saved])
    }

    private func handleBegin(_ context: NSExtensionContext, _ message: [String: Any]) {
        guard let sessionID = message["sessionID"] as? String, isValidSessionID(sessionID) else {
            respond(context, ["ok": false])
            return
        }
        do {
            try WebCaptureSessionStore.beginSession(id: sessionID)
            respond(context, ["ok": true])
        } catch {
            respond(context, ["ok": false])
        }
    }

    private func handleFrame(_ context: NSExtensionContext, _ message: [String: Any]) {
        guard let sessionID = message["sessionID"] as? String, isValidSessionID(sessionID),
              let index = message["index"] as? Int,
              let base64 = message["imageData"] as? String,
              let data = Data(base64Encoded: base64) else {
            respond(context, ["ok": false])
            return
        }
        do {
            try WebCaptureSessionStore.saveFrame(id: sessionID, data: data, index: index)
            respond(context, ["ok": true, "index": index])
        } catch {
            respond(context, ["ok": false])
        }
    }

    private func handleEnd(_ context: NSExtensionContext, _ message: [String: Any]) {
        guard let sessionID = message["sessionID"] as? String, isValidSessionID(sessionID),
              let frameCount = message["frameCount"] as? Int, frameCount > 0 else {
            respond(context, ["ok": false])
            return
        }
        do {
            try WebCaptureSessionStore.finishSession(
                id: sessionID,
                frameCount: frameCount,
                pageURL: message["pageURL"] as? String
            )
            respond(context, ["ok": true, "frameCount": frameCount])
        } catch {
            respond(context, ["ok": false])
        }
    }

    /// 防目录穿越：仅允许字母数字与连字符。
    private func isValidSessionID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 &&
            id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    private func respond(_ context: NSExtensionContext, _ payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
