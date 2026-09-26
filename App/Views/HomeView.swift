import StitchCore
import SwiftUI
import PhotoLibraryKit

struct HomeView: View {
    @StateObject private var viewModel = ScreenshotLibraryViewModel()
    @State private var direction: StitchDirection = .vertical
    @State private var showCompose = false
    @State private var showInbox = false
    @State private var inboxCount = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("相册来源", selection: Binding(
                    get: { viewModel.filter },
                    set: { viewModel.setFilter($0) }
                )) {
                    Text("截图").tag(PhotoLibraryService.AlbumFilter.screenshots)
                    Text("全部照片").tag(PhotoLibraryService.AlbumFilter.allPhotos)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                content

                Divider()

                bottomBar
            }
            .navigationTitle("StitchShot")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showInbox = true } label: {
                        Image(systemName: inboxCount > 0 ? "tray.full" : "tray")
                    }
                    .overlay(alignment: .topTrailing) {
                        if inboxCount > 0 {
                            Text("\(inboxCount)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Circle().fill(Color.red))
                                .offset(x: 10, y: -8)
                        }
                    }
                    .accessibilityLabel("收件箱")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.selectedIDs.isEmpty {
                        Button("清空") { viewModel.clearSelection() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            viewModel.requestAccessAndLoad()
            refreshInboxCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: URLRouter.switchTabNotification)) { note in
            guard (note.object as? AppRoute) == .inbox else { return }
            refreshInboxCount()
            showInbox = true
        }
        .sheet(isPresented: $showCompose) {
            StitchComposeView(assets: viewModel.selectedAssets, direction: direction)
        }
        .sheet(isPresented: $showInbox, onDismiss: refreshInboxCount) {
            InboxView()
        }
    }

    private func refreshInboxCount() {
        inboxCount = SharedInbox.pendingItems().count
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.authorizationStatus {
        case .authorized, .limited:
            ScreenshotGridView(viewModel: viewModel)
        case .denied, .restricted:
            PermissionDeniedView()
        default:
            PermissionRequestView { viewModel.requestAccessAndLoad() }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Picker("拼接方向", selection: $direction) {
                ForEach(StitchDirection.allCases, id: \.self) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }
            .pickerStyle(.segmented)

            Spacer()

            Text("已选 \(viewModel.selectedIDs.count) 张")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("拼接") { showCompose = true }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedIDs.count < 2)
        }
        .padding()
    }
}
