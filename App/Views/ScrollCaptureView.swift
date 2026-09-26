import SwiftUI
import ReplayKit
import StitchCore
import ScrollCaptureKit

struct ScrollCaptureView: View {
    static let broadcastExtensionBundleID = "com.example.stitchshot.StitchShotBroadcast"

    @State private var status: ScrollCaptureStatus? = ScrollCaptureStatusStore.load()
    @State private var showResult = false

    private let statusTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 12) {
                        BroadcastPickerRepresentable(
                            preferredExtensionBundleID: Self.broadcastExtensionBundleID
                        )
                        .frame(width: 48, height: 48)

                        Text("点击上方按钮开始录屏广播，然后切换到目标页面匀速滚动")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("开始录制")
                }

                Section {
                    StepRow(index: 1, text: "点击上方录屏按钮，选择「StitchShot 滚动截图」开始广播")
                    StepRow(index: 2, text: "切换到目标页面，匀速滚动到内容末尾")
                    StepRow(index: 3, text: "点击系统状态栏红色录制指示停止录制")
                    StepRow(index: 4, text: "回到本页查看并保存长截图")
                } header: {
                    Text("使用步骤")
                }

                Section {
                    if let status {
                        HStack {
                            Text("状态")
                            Spacer()
                            statusLabel(status.state)
                        }
                        HStack {
                            Text("捕获帧数")
                            Spacer()
                            Text("\(status.frameCount)").foregroundColor(.secondary)
                        }
                        if let strips = status.stripCount {
                            HStack {
                                Text("内容条带")
                                Spacer()
                                Text("\(strips)").foregroundColor(.secondary)
                            }
                        }
                        if let height = status.totalHeight {
                            HStack {
                                Text("预估高度")
                                Spacer()
                                Text("\(height) px").foregroundColor(.secondary)
                            }
                        }

                        if status.state == .finished, status.resultFileName != nil {
                            Button {
                                showResult = true
                            } label: {
                                Label("查看并保存长截图", systemImage: "photo")
                            }
                        }

                        if status.state == .failed {
                            Text("本次录制未捕获到内容，请重试")
                                .font(.footnote)
                                .foregroundColor(.orange)
                            Button("清除记录") {
                                clearSession()
                            }
                        }

                        if status.state == .recording || status.state == .paused {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(status.state == .recording ? "录制中…" : "已暂停")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("尚未捕获").foregroundColor(.secondary)
                    }
                } header: {
                    Text("捕获状态")
                }
            }
            .navigationTitle("滚动截图")
        }
        .navigationViewStyle(.stack)
        .onReceive(statusTimer) { _ in
            status = ScrollCaptureStatusStore.load()
        }
        .sheet(isPresented: $showResult) {
            if let sessionID = status?.resultFileName {
                ScrollCaptureResultView(sessionID: sessionID) {
                    status = ScrollCaptureStatusStore.load()
                }
            }
        }
    }

    private func statusLabel(_ state: ScrollCaptureStatus.State) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case .idle: return ("空闲", .secondary)
            case .recording: return ("录制中", .red)
            case .paused: return ("已暂停", .orange)
            case .finished: return ("已完成", .green)
            case .failed: return ("失败", .orange)
            }
        }()
        return Text(text).foregroundColor(color)
    }

    private func clearSession() {
        if let id = status?.resultFileName {
            ScrollCaptureComposer.deleteSession(id: id)
        }
        ScrollCaptureStatusStore.reset()
        status = nil
    }
}

private struct StepRow: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct BroadcastPickerRepresentable: UIViewRepresentable {
    let preferredExtensionBundleID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        picker.preferredExtensionBundleID = preferredExtensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
