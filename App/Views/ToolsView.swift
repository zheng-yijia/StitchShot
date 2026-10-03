import ImageEditorKit
import Photos
import SwiftUI

/// 工具页：编辑器各工具入口（选图后直达对应工具）。
struct ToolsView: View {

    private struct EditSession: Identifiable {
        let id = UUID()
        let image: UIImage
        let tool: EditorTool
    }

    private struct LiveSession: Identifiable {
        let id = UUID()
        let asset: PHAsset
    }

    private enum Route {
        case editor(EditorTool)
        case webCapture
        case livePhoto
    }

    private enum Sheet: Identifiable {
        case picker(EditorTool)
        case editor(EditSession)
        case videoPicker
        case livePhoto(LiveSession)

        var id: String {
            switch self {
            case .picker(let tool): return "picker-\(tool.rawValue)"
            case .editor(let session): return "editor-\(session.id.uuidString)"
            case .videoPicker: return "video-picker"
            case .livePhoto(let session): return "live-\(session.id.uuidString)"
            }
        }
    }

    private struct ToolRow: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let detail: String
        let route: Route
    }

    @State private var sheet: Sheet?

    private let rows: [ToolRow] = [
        ToolRow(name: "图片裁剪", icon: "crop", detail: "自由裁剪，手柄拖拽",
                route: .editor(.crop)),
        ToolRow(name: "马赛克", icon: "squareshape.dotted.squareshape", detail: "像素化 / 模糊涂抹",
                route: .editor(.mosaic)),
        ToolRow(name: "画线标注", icon: "pencil.tip.crop.circle", detail: "手绘、直线、箭头、矩形、椭圆",
                route: .editor(.annotate)),
        ToolRow(name: "文字水印", icon: "textformat", detail: "九宫格位置自定义水印",
                route: .editor(.watermark)),
        ToolRow(name: "纯色边框", icon: "square", detail: "为截图添加彩色边框",
                route: .editor(.border)),
        ToolRow(name: "带壳截图", icon: "iphone", detail: "iPhone 刘海 / 灵动岛 / iPad 外壳",
                route: .editor(.shell)),
        ToolRow(name: "状态栏清理", icon: "menubar.rectangle", detail: "纯色填充或 9:41 理想状态栏",
                route: .editor(.statusBar)),
        ToolRow(name: "视频转实况照片", icon: "livephoto", detail: "截取或来回循环，存为 Live Photo",
                route: .livePhoto),
        ToolRow(name: "网页快照", icon: "safari", detail: "Safari 扩展整页截取，在此拼接",
                route: .webCapture)
    ]

    var body: some View {
        NavigationView {
            List(rows) { row in
                rowContent(row)
            }
            .navigationTitle("工具")
        }
        .navigationViewStyle(.stack)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .picker(let tool):
                ImagePickerSheet { image in
                    self.sheet = .editor(EditSession(image: image, tool: tool))
                }
            case .editor(let session):
                NavigationView {
                    ImageEditorView(original: session.image, presetTool: session.tool)
                }
                .navigationViewStyle(.stack)
            case .videoPicker:
                VideoPickerSheet { asset in
                    self.sheet = .livePhoto(LiveSession(asset: asset))
                }
            case .livePhoto(let session):
                LivePhotoMakerView(asset: session.asset)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ row: ToolRow) -> some View {
        switch row.route {
        case .webCapture:
            NavigationLink(destination: WebCaptureListView()) {
                rowLabel(row)
            }
        case .editor(let tool):
            rowLabel(row)
                .contentShape(Rectangle())
                .onTapGesture { sheet = .picker(tool) }
        case .livePhoto:
            rowLabel(row)
                .contentShape(Rectangle())
                .onTapGesture { sheet = .videoPicker }
        }
    }

    private func rowLabel(_ row: ToolRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.icon)
                .font(.title3)
                .frame(width: 32)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                Text(row.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
