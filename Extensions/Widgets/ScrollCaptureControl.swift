import AppIntents
import StitchCore
import SwiftUI

#if canImport(ControlCenter)
import ControlCenter

/// 控制中心按钮：打开主 App 并跳转滚动截图页（iOS 18+）。
@available(iOS 18.0, *)
struct ScrollCaptureControlIntent: AppIntent {
    static let title: LocalizedStringResource = "打开滚动截图"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AppConstants.sharedDefaults.set("scroll", forKey: "pendingRoute")
        return .result()
    }
}

@available(iOS 18.0, *)
struct ScrollCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.example.stitchshot.control.scrollcapture") {
            ControlWidgetButton(action: ScrollCaptureControlIntent()) {
                Label("滚动截图", systemImage: "scroll")
            }
        }
    }
}
#endif
