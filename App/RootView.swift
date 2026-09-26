import SwiftUI

struct RootView: View {
    @State private var selection = 0
    @State private var automationMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("拼接", systemImage: "square.grid.2x2") }
                .tag(0)
            ScrollCaptureView()
                .tabItem { Label("滚动截图", systemImage: "scroll") }
                .tag(1)
            ToolsView()
                .tabItem { Label("工具", systemImage: "wrench.and.screwdriver") }
                .tag(2)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
        .onReceive(NotificationCenter.default.publisher(for: URLRouter.switchTabNotification)) { note in
            guard let route = note.object as? AppRoute else { return }
            selection = tabIndex(for: route)
        }
        .onReceive(NotificationCenter.default.publisher(for: AutomationService.completionNotification)) { note in
            automationMessage = note.object as? String
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active, let route = URLRouter.consumePendingRoute() else { return }
            selection = tabIndex(for: route)
        }
        .alert("自动化", isPresented: Binding(
            get: { automationMessage != nil },
            set: { if !$0 { automationMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(automationMessage ?? "")
        }
    }

    private func tabIndex(for route: AppRoute) -> Int {
        switch route {
        case .stitch, .inbox: return 0
        case .scroll: return 1
        case .settings: return 3
        }
    }
}
