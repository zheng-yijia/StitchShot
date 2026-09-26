import WidgetKit
import SwiftUI

struct QuickActionsEntry: TimelineEntry {
    let date: Date
}

struct QuickActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        completion(QuickActionsEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        completion(Timeline(entries: [QuickActionsEntry(date: Date())], policy: .never))
    }
}

struct QuickActionsWidgetView: View {
    var body: some View {
        HStack(spacing: 0) {
            actionLink(
                title: "拼接",
                systemImage: "square.grid.2x2",
                url: "stitchshot://stitch"
            )
            Divider().padding(.vertical, 12)
            actionLink(
                title: "滚动截图",
                systemImage: "scroll",
                url: "stitchshot://scroll"
            )
        }
    }

    private func actionLink(title: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct QuickActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.example.stitchshot.quickactions", provider: QuickActionsProvider()) { _ in
            QuickActionsWidgetView()
        }
        .configurationDisplayName("StitchShot 快捷操作")
        .description("一键开始拼接或滚动截图。")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct StitchShotWidgets: WidgetBundle {
    var body: some Widget {
        QuickActionsWidget()
        #if canImport(ControlCenter)
        if #available(iOS 18.0, *) {
            ScrollCaptureControl()
        }
        #endif
    }
}
