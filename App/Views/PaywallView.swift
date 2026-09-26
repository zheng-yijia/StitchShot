import SwiftUI

/// Pro 升级页：买断制解锁带壳截图等高级能力。
struct PaywallView: View {
    @ObservedObject private var manager = ProUpgradeManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showResult = false
    @State private var resultMessage = ""

    private struct Feature {
        let icon: String
        let text: String
    }

    private let features: [Feature] = [
        Feature(icon: "iphone", text: "带壳截图：iPhone 刘海 / 灵动岛 / iPad 外壳"),
        Feature(icon: "textformat", text: "自动化 mockup 参数全套可用"),
        Feature(icon: "star", text: "支持独立开发，后续高级功能优先解锁")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.yellow)

                Text("StitchShot Pro")
                    .font(.title.bold())

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.text) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .frame(width: 24)
                                .foregroundColor(.accentColor)
                            Text(feature.text)
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                if manager.isPurchasing {
                    ProgressView()
                } else {
                    Button {
                        Task { await buy() }
                    } label: {
                        Text(manager.isPro ? "已解锁 Pro" : "买断升级 \(manager.priceText)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isPro)
                    .padding(.horizontal, 24)

                    Button("恢复购买") {
                        Task {
                            await manager.restore()
                            resultMessage = manager.isPro ? "已恢复 Pro 权益" : "未找到可恢复的购买"
                            showResult = true
                        }
                    }
                    .font(.subheadline)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("升级 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .alert(resultMessage, isPresented: $showResult) {
            Button("好", role: .cancel) {}
        }
    }

    private func buy() async {
        let success = await manager.purchase()
        resultMessage = success ? "升级成功，感谢支持" : "购买未完成"
        showResult = true
        if success {
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        }
    }
}
