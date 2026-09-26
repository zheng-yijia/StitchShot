import StitchCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("settings.deleteSourceAfterStitch", store: AppConstants.sharedDefaults)
    private var deleteSourceAfterStitch = false

    @AppStorage("settings.cleanStatusBar", store: AppConstants.sharedDefaults)
    private var cleanStatusBar = true

    @ObservedObject private var pro = ProUpgradeManager.shared
    @State private var showPaywall = false
    @State private var showClearCacheConfirm = false
    @State private var cacheCleared = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Pro")) {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                            Text("StitchShot Pro")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(pro.isPro ? "已解锁" : "买断升级 \(pro.priceText)")
                                .foregroundColor(.secondary)
                        }
                    }
                    if !pro.isPro {
                        Button("恢复购买") {
                            Task { await pro.restore() }
                        }
                    }
                }

                Section(header: Text("拼接")) {
                    Toggle("拼接后删除源截图", isOn: $deleteSourceAfterStitch)
                    Toggle("自动清理状态栏", isOn: $cleanStatusBar)
                }

                Section(header: Text("自动化")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL Scheme")
                            .font(.subheadline)
                        Text("stitchshot://x-callback-url/vert?in=clipboard&out=save")
                        Text("stitchshot://x-callback-url/hori?in=latest&count=3")
                        Text("参数：in / out / delete_source / mockup / clean_status / x-success / x-error")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section(header: Text("存储")) {
                    Button("清理共享缓存") {
                        showClearCacheConfirm = true
                    }
                    .foregroundColor(.red)
                }

                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("项目")
                        Spacer()
                        Text("对标 Picsew 全功能复刻")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .confirmationDialog("删除收件箱、网页快照与滚动截图的缓存文件？", isPresented: $showClearCacheConfirm, titleVisibility: .visible) {
            Button("清理", role: .destructive) {
                SharedInbox.removeAll()
                WebCaptureSessionStore.deleteAll()
                ScrollCaptureSessionStore.deleteAllSessions()
                cacheCleared = true
            }
            Button("取消", role: .cancel) {}
        }
        .alert("缓存已清理", isPresented: $cacheCleared) {
            Button("好", role: .cancel) {}
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }
}
