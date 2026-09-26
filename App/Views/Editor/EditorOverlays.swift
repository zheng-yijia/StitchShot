import ImageEditorKit
import SwiftUI

/// 计算图片在给定容器内 aspect-fit 后的显示矩形。
func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(x: (container.width - size.width) / 2,
                  y: (container.height - size.height) / 2,
                  width: size.width, height: size.height)
}

// MARK: - 裁剪覆盖层

/// 四角手柄 + 内部拖动移动的裁剪框，draft 为视图坐标。
struct CropOverlay: View {
    let displayRect: CGRect
    @Binding var draft: CGRect?

    private enum DragMode {
        case none, move, topLeft, topRight, bottomLeft, bottomRight
    }

    @State private var mode: DragMode = .none
    @State private var startRect: CGRect = .zero

    private let handleRadius: CGFloat = 16
    private let minSize: CGFloat = 40

    var body: some View {
        if let draft {
            dimRects(around: draft)
            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: draft.width, height: draft.height)
                .position(x: draft.midX, y: draft.midY)
            gridLines(in: draft)
            ForEach(corners(of: draft), id: \.self) { point in
                Circle()
                    .fill(Color.white)
                    .frame(width: handleRadius * 2, height: handleRadius * 2)
                    .shadow(radius: 2)
                    .position(point)
            }
        }
        Color.clear
            .contentShape(Rectangle())
            .gesture(dragGesture)
    }

    private func dimRects(around rect: CGRect) -> some View {
        let dim = Color.black.opacity(0.45)
        return ZStack {
            dim.frame(width: displayRect.width, height: max(0, rect.minY - displayRect.minY))
                .position(x: displayRect.midX, y: (displayRect.minY + rect.minY) / 2)
            dim.frame(width: displayRect.width, height: max(0, displayRect.maxY - rect.maxY))
                .position(x: displayRect.midX, y: (rect.maxY + displayRect.maxY) / 2)
            dim.frame(width: max(0, rect.minX - displayRect.minX), height: rect.height)
                .position(x: (displayRect.minX + rect.minX) / 2, y: rect.midY)
            dim.frame(width: max(0, displayRect.maxX - rect.maxX), height: rect.height)
                .position(x: (rect.maxX + displayRect.maxX) / 2, y: rect.midY)
        }
    }

    private func gridLines(in rect: CGRect) -> some View {
        Path { path in
            for i in 1..<3 {
                let fx = rect.minX + rect.width * CGFloat(i) / 3
                let fy = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: fx, y: rect.minY))
                path.addLine(to: CGPoint(x: fx, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: fy))
                path.addLine(to: CGPoint(x: rect.maxX, y: fy))
            }
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [rect.origin,
         CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY),
         CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func hitMode(at point: CGPoint, rect: CGRect) -> DragMode {
        let cornerPoints = corners(of: rect)
        let modes: [DragMode] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for (index, corner) in cornerPoints.enumerated() where hypot(point.x - corner.x, point.y - corner.y) <= handleRadius * 2 {
            return modes[index]
        }
        return rect.contains(point) ? .move : .none
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let current = draft else { return }
                if mode == .none {
                    let hit = hitMode(at: value.startLocation, rect: current)
                    guard hit != .none else { return }
                    mode = hit
                    startRect = current
                }
                draft = transformed(startRect, mode: mode, translation: value.translation)
            }
            .onEnded { _ in mode = .none }
    }

    private func transformed(_ rect: CGRect, mode: DragMode, translation: CGSize) -> CGRect {
        var r = rect
        switch mode {
        case .move:
            r.origin.x += translation.width
            r.origin.y += translation.height
            r.origin.x = min(max(r.origin.x, displayRect.minX), displayRect.maxX - r.width)
            r.origin.y = min(max(r.origin.y, displayRect.minY), displayRect.maxY - r.height)
        case .topLeft:
            r.origin.x += translation.width
            r.origin.y += translation.height
            r.size.width -= translation.width
            r.size.height -= translation.height
        case .topRight:
            r.origin.y += translation.height
            r.size.width += translation.width
            r.size.height -= translation.height
        case .bottomLeft:
            r.origin.x += translation.width
            r.size.width -= translation.width
            r.size.height += translation.height
        case .bottomRight:
            r.size.width += translation.width
            r.size.height += translation.height
        case .none:
            break
        }
        if mode != .move {
            if r.width < minSize {
                if mode == .topLeft || mode == .bottomLeft { r.origin.x = r.maxX - minSize }
                r.size.width = minSize
            }
            if r.height < minSize {
                if mode == .topLeft || mode == .topRight { r.origin.y = r.maxY - minSize }
                r.size.height = minSize
            }
            r.size.width = min(r.width, displayRect.width)
            r.size.height = min(r.height, displayRect.height)
            r.origin.x = min(max(r.origin.x, displayRect.minX), displayRect.maxX - r.width)
            r.origin.y = min(max(r.origin.y, displayRect.minY), displayRect.maxY - r.height)
        }
        return r
    }
}

// MARK: - 马赛克画布

/// 拖动手势收集笔迹（视图坐标），结束时回调归一化点列。
struct MosaicCanvas: View {
    let displayRect: CGRect
    let widthFraction: CGFloat
    let onCommit: ([CGPoint]) -> Void

    @State private var draft: [CGPoint] = []

    var body: some View {
        Path { path in
            guard let first = draft.first else { return }
            path.move(to: first)
            for point in draft.dropFirst() {
                path.addLine(to: point)
            }
        }
        .stroke(Color.white.opacity(0.55),
                style: StrokeStyle(lineWidth: max(2, widthFraction * displayRect.width), lineCap: .round, lineJoin: .round))
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard displayRect.contains(value.location) else { return }
                        draft.append(value.location)
                    }
                    .onEnded { _ in
                        let normalized = draft.map {
                            CGPoint(x: ($0.x - displayRect.minX) / displayRect.width,
                                    y: ($0.y - displayRect.minY) / displayRect.height)
                        }
                        if normalized.count > 1 { onCommit(normalized) }
                        draft = []
                    }
            )
    }
}

// MARK: - 标注画布

/// 形状类为两点拖动，手绘为自由路径；回调归一化点列。
struct AnnotateCanvas: View {
    let displayRect: CGRect
    let kind: AnnotationKind
    let color: UIColor
    let widthFraction: CGFloat
    let onCommit: ([CGPoint]) -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    @State private var freehand: [CGPoint] = []

    private var lineWidth: CGFloat { max(2, widthFraction * displayRect.width) }
    private var swiftUIColor: Color { Color(color) }

    var body: some View {
        transientShape
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location.clamped(to: displayRect)
                        if start == nil { start = value.startLocation.clamped(to: displayRect) }
                        current = point
                        if kind == .freehand { freehand.append(point) }
                    }
                    .onEnded { _ in
                        commit()
                        start = nil
                        current = nil
                        freehand = []
                    }
            )
    }

    @ViewBuilder
    private var transientShape: some View {
        switch kind {
        case .freehand:
            Path { path in
                guard let first = freehand.first else { return }
                path.move(to: first)
                for point in freehand.dropFirst() { path.addLine(to: point) }
            }
            .stroke(swiftUIColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case .line:
            if let start, let current {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: current)
                }
                .stroke(swiftUIColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        case .arrow:
            if let start, let current {
                arrowPath(from: start, to: current)
                    .stroke(swiftUIColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        case .rectangle:
            if let start, let current {
                Rectangle()
                    .stroke(swiftUIColor, lineWidth: lineWidth)
                    .frame(width: abs(current.x - start.x), height: abs(current.y - start.y))
                    .position(x: (start.x + current.x) / 2, y: (start.y + current.y) / 2)
            }
        case .ellipse:
            if let start, let current {
                Ellipse()
                    .stroke(swiftUIColor, lineWidth: lineWidth)
                    .frame(width: abs(current.x - start.x), height: abs(current.y - start.y))
                    .position(x: (start.x + current.x) / 2, y: (start.y + current.y) / 2)
            }
        }
    }

    private func arrowPath(from start: CGPoint, to end: CGPoint) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen = max(lineWidth * 4, 14)
            let spread: CGFloat = .pi / 7
            for sign: CGFloat in [1, -1] {
                let a = angle + .pi + sign * spread
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x + headLen * cos(a), y: end.y + headLen * sin(a)))
            }
        }
    }

    private func commit() {
        let normalize: (CGPoint) -> CGPoint = {
            CGPoint(x: ($0.x - displayRect.minX) / displayRect.width,
                    y: ($0.y - displayRect.minY) / displayRect.height)
        }
        switch kind {
        case .freehand:
            let points = freehand.map(normalize)
            if points.count > 1 { onCommit(points) }
        case .line, .arrow, .rectangle, .ellipse:
            guard let start, let current else { return }
            let a = normalize(start)
            let b = normalize(current)
            guard hypot(a.x - b.x, a.y - b.y) > 0.005 else { return }
            onCommit([a, b])
        }
    }
}

private extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(x, rect.minX), rect.maxX),
                y: min(max(y, rect.minY), rect.maxY))
    }
}
