import UIKit

public enum EditorTool: String, CaseIterable, Identifiable {
    case crop
    case mosaic
    case annotate
    case watermark
    case border
    case shell
    case statusBar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crop: return "裁剪"
        case .mosaic: return "马赛克"
        case .annotate: return "标注"
        case .watermark: return "水印"
        case .border: return "边框"
        case .shell: return "带壳"
        case .statusBar: return "状态栏"
        }
    }

    public var icon: String {
        switch self {
        case .crop: return "crop"
        case .mosaic: return "squareshape.dotted.squareshape"
        case .annotate: return "pencil.tip.crop.circle"
        case .watermark: return "textformat"
        case .border: return "square"
        case .shell: return "iphone"
        case .statusBar: return "menubar.rectangle"
        }
    }

    /// 需要在预览上直接手势交互的工具。
    public var isInteractive: Bool {
        switch self {
        case .crop, .mosaic, .annotate: return true
        case .watermark, .border, .shell, .statusBar: return false
        }
    }
}

// MARK: - 编辑模型（值类型，全部归一化坐标，分辨率无关）

/// 马赛克笔迹：点为相对图宽的归一化坐标，宽度为图宽分数。
public struct MosaicStroke {
    public var points: [CGPoint]
    public var widthFraction: CGFloat
    public var style: MosaicStyle

    public init(points: [CGPoint], widthFraction: CGFloat, style: MosaicStyle) {
        self.points = points
        self.widthFraction = widthFraction
        self.style = style
    }
}

public enum MosaicStyle: String, CaseIterable {
    case pixelate
    case blur

    public var displayName: String {
        switch self {
        case .pixelate: return "像素化"
        case .blur: return "模糊"
        }
    }
}

public enum AnnotationKind: String, CaseIterable {
    case freehand
    case line
    case arrow
    case rectangle
    case ellipse

    public var displayName: String {
        switch self {
        case .freehand: return "手绘"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        }
    }
}

/// 标注图元：形状类 points 为 [起点, 终点]，手绘为完整路径（均归一化）。
public struct AnnotationItem {
    public var kind: AnnotationKind
    public var color: UIColor
    public var widthFraction: CGFloat
    public var points: [CGPoint]

    public init(kind: AnnotationKind, color: UIColor, widthFraction: CGFloat, points: [CGPoint]) {
        self.kind = kind
        self.color = color
        self.widthFraction = widthFraction
        self.points = points
    }
}

public enum WatermarkPosition: String, CaseIterable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
}

public struct WatermarkConfig {
    public var text: String
    public var color: UIColor
    public var opacity: CGFloat
    public var sizeFraction: CGFloat
    public var position: WatermarkPosition

    public init(
        text: String = "@StitchShot",
        color: UIColor = .white,
        opacity: CGFloat = 0.8,
        sizeFraction: CGFloat = 0.05,
        position: WatermarkPosition = .bottomRight
    ) {
        self.text = text
        self.color = color
        self.opacity = opacity
        self.sizeFraction = sizeFraction
        self.position = position
    }
}

public struct BorderConfig {
    public var thicknessFraction: CGFloat
    public var color: UIColor

    public init(thicknessFraction: CGFloat = 0.05, color: UIColor = .white) {
        self.thicknessFraction = thicknessFraction
        self.color = color
    }
}

public enum DeviceKind: String, CaseIterable {
    case iPhoneNotch
    case iPhoneDynamicIsland
    case iPad

    public var displayName: String {
        switch self {
        case .iPhoneNotch: return "iPhone 刘海"
        case .iPhoneDynamicIsland: return "iPhone 灵动岛"
        case .iPad: return "iPad"
        }
    }
}

public struct ShellConfig {
    public var device: DeviceKind
    public var background: UIColor

    public init(device: DeviceKind = .iPhoneDynamicIsland, background: UIColor = .darkGray) {
        self.device = device
        self.background = background
    }
}

public enum StatusBarCleanStyle: String, CaseIterable {
    case solid
    case idealized

    public var displayName: String {
        switch self {
        case .solid: return "纯色填充"
        case .idealized: return "理想状态栏"
        }
    }
}

public struct StatusBarCleanConfig {
    public var heightFraction: CGFloat
    public var style: StatusBarCleanStyle

    public init(heightFraction: CGFloat = 0.055, style: StatusBarCleanStyle = .solid) {
        self.heightFraction = heightFraction
        self.style = style
    }
}

/// 非破坏性编辑模型。渲染顺序：状态栏 → 裁剪 → 马赛克 → 标注 → 水印 → 边框 → 带壳。
/// 裁剪矩形为原图像素坐标；马赛克与标注为裁剪后图像的归一化坐标。
public struct EditModel {
    public var base: UIImage
    public var statusBarClean: StatusBarCleanConfig?
    public var cropRect: CGRect?
    public var mosaicStrokes: [MosaicStroke]
    public var annotations: [AnnotationItem]
    public var watermark: WatermarkConfig?
    public var border: BorderConfig?
    public var shell: ShellConfig?

    public init(base: UIImage) {
        self.base = base
        self.statusBarClean = nil
        self.cropRect = nil
        self.mosaicStrokes = []
        self.annotations = []
        self.watermark = nil
        self.border = nil
        self.shell = nil
    }

    public var hasMarks: Bool {
        !mosaicStrokes.isEmpty || !annotations.isEmpty
    }
}
