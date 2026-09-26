import SwiftUI

@main
struct StitchShotApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { URLRouter.handle($0) }
        }
    }
}
