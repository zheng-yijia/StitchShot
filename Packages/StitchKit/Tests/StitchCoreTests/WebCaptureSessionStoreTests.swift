import XCTest
@testable import StitchCore

final class WebCaptureSessionStoreTests: XCTestCase {

    private let sessionID = "web-test-1"

    override func tearDown() {
        WebCaptureSessionStore.delete(id: sessionID)
        WebCaptureSessionStore.delete(id: "web-test-2")
        super.tearDown()
    }

    private func pngData(_ byte: UInt8) -> Data {
        // 内容无需为合法 PNG，存储层只负责读写
        Data([0x89, 0x50, 0x4E, 0x47, byte])
    }

    func testBeginFrameEndRoundtrip() throws {
        try WebCaptureSessionStore.beginSession(id: sessionID)
        try WebCaptureSessionStore.saveFrame(id: sessionID, data: pngData(1), index: 0)
        try WebCaptureSessionStore.saveFrame(id: sessionID, data: pngData(2), index: 1)

        let session = try WebCaptureSessionStore.finishSession(id: sessionID, frameCount: 2, pageURL: "https://example.com/page")
        XCTAssertEqual(session.frameFiles.count, 2)
        XCTAssertEqual(session.pageURL, "https://example.com/page")

        let listed = WebCaptureSessionStore.sessions()
        XCTAssertTrue(listed.contains { $0.id == sessionID })

        let frames = WebCaptureSessionStore.loadFrames(session)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], pngData(1))
        XCTAssertEqual(frames[1], pngData(2))
    }

    func testFinishFailsWhenFrameMissing() throws {
        try WebCaptureSessionStore.beginSession(id: "web-test-2")
        try WebCaptureSessionStore.saveFrame(id: "web-test-2", data: pngData(1), index: 0)
        XCTAssertThrowsError(
            try WebCaptureSessionStore.finishSession(id: "web-test-2", frameCount: 2, pageURL: nil)
        )
        XCTAssertFalse(WebCaptureSessionStore.sessions().contains { $0.id == "web-test-2" })
    }

    func testDeleteRemovesSession() throws {
        try WebCaptureSessionStore.beginSession(id: sessionID)
        try WebCaptureSessionStore.saveFrame(id: sessionID, data: pngData(1), index: 0)
        _ = try WebCaptureSessionStore.finishSession(id: sessionID, frameCount: 1, pageURL: nil)

        WebCaptureSessionStore.delete(id: sessionID)
        XCTAssertFalse(WebCaptureSessionStore.sessions().contains { $0.id == sessionID })
    }
}
