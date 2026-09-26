import SwiftUI
import StitchCore
import StitchEngine

/// 手动微调：逐条接缝预览，拖拽或步进调整重叠量，支持单缝重新自动检测。
struct SeamAdjustmentView: View {
    let images: [UIImage]
    let onApply: (StitchPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var plan: StitchPlan
    @State private var selected = 0
    @State private var redetecting = false

    init(images: [UIImage], plan: StitchPlan, onApply: @escaping (StitchPlan) -> Void) {
        self.images = images
        self._plan = State(initialValue: plan)
        self.onApply = onApply
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                if plan.seamCount > 1 {
                    Picker("接缝", selection: $selected) {
                        ForEach(0..<plan.seamCount, id: \.self) { index in
                            Text("接缝 \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                SeamEditor(images: images, plan: $plan, index: selected)
                    .padding(.horizontal)

                infoRow

                nudgeButtons

                Divider()

                HStack {
                    Button { redetect() } label: {
                        Label(redetecting ? "检测中…" : "重新检测本缝", systemImage: "arrow.clockwise")
                    }
                    .disabled(redetecting)
                    Spacer()
                    Button("完成") {
                        onApply(plan)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("调整拼接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var infoRow: some View {
        let seam = plan.seams[selected]
        return HStack(spacing: 8) {
            Text("重叠 \(seam.overlap) px")
                .font(.subheadline.monospacedDigit())
            Text(methodLabel(seam.method))
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
            if seam.userAdjusted {
                Text("已手动调整")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            } else {
                Text("置信度 \(Int(seam.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(seam.confidence < 0.4 ? .orange : .secondary)
            }
        }
    }

    private var nudgeButtons: some View {
        HStack(spacing: 16) {
            Button("-10") { nudge(-10) }
            Button("-1") { nudge(-1) }
            Text("微调")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("+1") { nudge(1) }
            Button("+10") { nudge(10) }
        }
        .buttonStyle(.bordered)
    }

    private func nudge(_ delta: Int) {
        plan.adjustSeam(at: selected, newOverlap: plan.seams[selected].overlap + delta)
    }

    private func redetect() {
        redetecting = true
        let first = images[selected]
        let second = images[selected + 1]
        let direction = plan.direction
        Task {
            let seam = await StitchEngine.detectOverlap(from: first, to: second, direction: direction)
            plan.replaceSeam(at: selected, with: seam)
            redetecting = false
        }
    }

    private func methodLabel(_ method: StitchMethod) -> String {
        switch method {
        case .templateMatch: return "模板匹配"
        case .visionRegistration: return "视觉配准"
        case .none: return "未检测到"
        }
    }
}

/// 单条接缝编辑器：上方显示上图尾部，下方显示下图自切边起的内容，拖拽中线调整重叠。
private struct SeamEditor: View {
    let images: [UIImage]
    @Binding var plan: StitchPlan
    let index: Int

    @State private var dragStartOverlap: Int?

    /// 接缝两侧各预览的像素长度。
    private let previewLength = 420

    var body: some View {
        GeometryReader { geometry in
            let seam = plan.seams[index]
            let scale = images[index].cgImage.map { CGFloat($0.width) / max(geometry.size.width, 1) } ?? 1
            preview(seam: seam)
                .contentShape(Rectangle())
                .gesture(dragGesture(scale: scale))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 420)
        .clipped()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func preview(seam: Seam) -> some View {
        if plan.direction == .vertical {
            VStack(spacing: 0) {
                cropImage(images[index], rect: upperTailRect(seam: seam))
                divider(vertical: true)
                cropImage(images[index + 1], rect: lowerHeadRect(seam: seam))
            }
        } else {
            HStack(spacing: 0) {
                cropImage(images[index], rect: upperTailRect(seam: seam))
                divider(vertical: false)
                cropImage(images[index + 1], rect: lowerHeadRect(seam: seam))
            }
        }
    }

    private func divider(vertical: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: vertical ? nil : 2, height: vertical ? 2 : nil)
            Image(systemName: vertical ? "arrow.up.and.down.circle.fill" : "arrow.left.and.right.circle.fill")
                .font(.title3)
                .foregroundColor(.accentColor)
                .background(Circle().fill(Color.white))
        }
    }

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOverlap == nil {
                    dragStartOverlap = plan.seams[index].overlap
                }
                guard let start = dragStartOverlap else { return }
                let translation = plan.direction == .vertical ? value.translation.height : value.translation.width
                plan.adjustSeam(at: index, newOverlap: start + Int((translation * scale).rounded()))
            }
            .onEnded { _ in
                dragStartOverlap = nil
            }
    }

    /// 上图（或左图）尾部保留区域。
    private func upperTailRect(seam: Seam) -> CGRect {
        let size = plan.imageSizes[index]
        switch plan.direction {
        case .vertical:
            let height = min(CGFloat(previewLength), size.height)
            return CGRect(x: 0, y: size.height - height, width: size.width, height: height)
        case .horizontal:
            let width = min(CGFloat(previewLength), size.width)
            return CGRect(x: size.width - width, y: 0, width: width, height: size.height)
        }
    }

    /// 下图（或右图）自切边起的新内容区域。
    private func lowerHeadRect(seam: Seam) -> CGRect {
        let size = plan.imageSizes[index + 1]
        let overlap = CGFloat(seam.overlap)
        switch plan.direction {
        case .vertical:
            let height = max(1, min(CGFloat(previewLength), size.height - overlap))
            return CGRect(x: 0, y: overlap, width: size.width, height: height)
        case .horizontal:
            let width = max(1, min(CGFloat(previewLength), size.width - overlap))
            return CGRect(x: overlap, y: 0, width: width, height: size.height)
        }
    }

    private func cropImage(_ image: UIImage, rect: CGRect) -> some View {
        Group {
            if let cgImage = image.cgImage, let cropped = cgImage.cropping(to: rect) {
                Image(uiImage: UIImage(cgImage: cropped))
                    .resizable()
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
    }
}
