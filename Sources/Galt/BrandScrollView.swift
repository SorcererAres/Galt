import AppKit
import SwiftUI

/// 品牌化滚动容器：隐藏系统滚动条，叠一条自绘的圆角胶囊。
///
/// 设计取舍：滚动位置不走 SwiftUI 的 PreferenceKey（长列表里易抖动、滞后），
/// 而是放一枚零尺寸的 AppKit 探针进内容树，借 `enclosingScrollView` 拿到底层
/// `NSScrollView`，直接读 clip 的 bounds —— 精确、跟手，还能反向驱动滚动以支持拖拽。
///
/// 视觉对齐 Galt 规范：中性色胶囊（`Palette.textTertiary`）、全圆角、滚动 / 悬停淡入、
/// 空闲约 1.1s 后淡出；内容不足一屏时整体隐藏。
///
/// 这是「滚动条叠在内容右缘」的便捷版。若想把滚动条挪到内容外侧的独立一列
/// （不覆盖卡片），改用 `BrandScrollViewCore` + 外置的 `BrandScrollbar`，
/// 二者共享同一个父级持有的 `ScrollMetrics`。
struct BrandScrollView<Content: View>: View {
    /// 滚动条相对滚动区边缘的内缩。带圆角描边的容器内使用时，传入正值让胶囊
    /// 避开圆角、不溢出边框（如 `EdgeInsets(top: 12, …, trailing: 8)`）。默认贴边。
    var scrollbarInset: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content

    @StateObject private var metrics = ScrollMetrics()

    var body: some View {
        BrandScrollViewCore(metrics: metrics, content: content)
            .overlay(alignment: .trailing) {
                BrandScrollbar(metrics: metrics)
                    .frame(width: 14) // 叠加版：右缘细条，仅这条带可点击
                    .padding(scrollbarInset)
            }
    }
}

/// 滚动核心：滚动视图 + AppKit 探针 + 滚动状态广播，**不含**滚动条本体。
/// 由父视图持有 `metrics`，从而能把 `BrandScrollbar` 摆到任意外侧容器。
struct BrandScrollViewCore<Content: View>: View {
    @ObservedObject var metrics: ScrollMetrics
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            content()
                .background(ScrollProbe(metrics: metrics)) // 探针随内容进入 documentView
        }
        .scrollIndicators(.never)
        // 滚动期间向子树广播：让卡片忽略「内容从静止光标下滑过」误触的 hover
        .environment(\.scrollIsActive, metrics.isScrolling)
    }
}

// MARK: - 滚动度量（由 AppKit 探针实时回填）

final class ScrollMetrics: ObservableObject {
    @Published var contentHeight: CGFloat = 0   // documentView 高度
    @Published var viewportHeight: CGFloat = 0  // clip 可视高度
    @Published var offsetY: CGFloat = 0         // 顶部已滚出的距离
    @Published var isScrolling = false          // 正在滚动（含短暂冷却）
    weak var scrollView: NSScrollView?

    private var scrollEndWork: DispatchWorkItem?

    var maxOffset: CGFloat { max(contentHeight - viewportHeight, 0) }
    var scrollable: Bool { maxOffset > 0.5 }

    /// 标记一次滚动活动；停止 0.15s 后复位，留出冷却避免末帧误触。
    func markScrolling() {
        if !isScrolling { isScrolling = true }
        scrollEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.isScrolling = false }
        scrollEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// 拖拽滑块时反向驱动 NSScrollView 滚动。
    func scroll(toOffset y: CGFloat) {
        guard let scrollView, let clip = scrollView.contentView as NSClipView? else { return }
        let clamped = min(max(y, 0), maxOffset)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: clamped))
        scrollView.reflectScrolledClipView(clip)
    }
}

// MARK: - AppKit 探针：定位底层 NSScrollView 并观测滚动

private struct ScrollProbe: NSViewRepresentable {
    let metrics: ScrollMetrics

    func makeCoordinator() -> Coordinator { Coordinator(metrics: metrics) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // 等视图进入层级后再向上找 enclosingScrollView
        DispatchQueue.main.async { context.coordinator.connect(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.connect(from: nsView) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    final class Coordinator {
        private let metrics: ScrollMetrics
        private weak var scrollView: NSScrollView?
        private var observers: [NSObjectProtocol] = []

        init(metrics: ScrollMetrics) { self.metrics = metrics }

        func connect(from view: NSView) {
            guard let scrollView = view.enclosingScrollView, scrollView !== self.scrollView else {
                if scrollView != nil { sync() } // 同一个滚动视图，刷新一次度量
                return
            }
            disconnect()
            self.scrollView = scrollView
            metrics.scrollView = scrollView

            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification,
                                            object: clip, queue: .main) { [weak self] _ in self?.sync() })
            observers.append(nc.addObserver(forName: NSView.frameDidChangeNotification,
                                            object: scrollView, queue: .main) { [weak self] _ in self?.sync() })
            sync()
        }

        func disconnect() {
            let nc = NotificationCenter.default
            observers.forEach { nc.removeObserver($0) }
            observers.removeAll()
            scrollView = nil
        }

        private func sync() {
            guard let scrollView else { return }
            let clip = scrollView.contentView
            let viewport = clip.bounds.height
            let content = scrollView.documentView?.frame.height ?? viewport
            let offset = clip.bounds.origin.y
            // 仅在变化时写回，避免无谓刷新
            if abs(metrics.viewportHeight - viewport) > 0.5 { metrics.viewportHeight = viewport }
            if abs(metrics.contentHeight - content) > 0.5 { metrics.contentHeight = content }
            if abs(metrics.offsetY - offset) > 0.5 {
                metrics.offsetY = offset
                metrics.markScrolling()
            }
        }
    }
}

// MARK: - 环境值：滚动是否进行中

private struct ScrollIsActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 列表是否正在滚动；子视图据此屏蔽滚动期间的误触 hover。
    var scrollIsActive: Bool {
        get { self[ScrollIsActiveKey.self] }
        set { self[ScrollIsActiveKey.self] = newValue }
    }
}

// MARK: - 自绘胶囊滚动条

/// 自绘胶囊滚动条。**宽度无关**：填满所在容器，胶囊贴容器右缘绘制，整列可点击 / 拖拽。
/// 由调用方决定它的位置与列宽——叠加在内容右缘（细条）或独立摆进外侧一列均可。
struct BrandScrollbar: View {
    @ObservedObject var metrics: ScrollMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 视觉参数
    private let thumbWidth: CGFloat = 6
    private let inset: CGFloat = 4
    private let minThumb: CGFloat = 28

    @State private var visible = false
    @State private var hovering = false
    @State private var dragging = false
    @State private var dragStartOffset: CGFloat = 0
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.height - inset * 2, 0)
            let ratio = metrics.contentHeight > 0
                ? min(metrics.viewportHeight / metrics.contentHeight, 1) : 1
            let thumbH = max(minThumb, track * ratio)
            let maxThumbY = max(track - thumbH, 0)
            let progress = metrics.maxOffset > 0
                ? min(max(metrics.offsetY / metrics.maxOffset, 0), 1) : 0
            let thumbY = inset + progress * maxThumbY

            if metrics.scrollable {
                Capsule(style: .continuous)
                    .fill(thumbColor)
                    .frame(width: thumbWidth, height: thumbH)
                    .frame(maxWidth: .infinity, alignment: .trailing) // 胶囊贴所在列右缘
                    .contentShape(Rectangle())                        // 整列宽度可点击 / 拖拽
                    .offset(y: thumbY)
                    .opacity(visible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: visible)
                    .animation(GaltDesign.Motion.hover(reduceMotion), value: thumbColor)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !dragging { dragging = true; dragStartOffset = metrics.offsetY }
                                guard maxThumbY > 0 else { return }
                                let delta = value.translation.height / maxThumbY * metrics.maxOffset
                                metrics.scroll(toOffset: dragStartOffset + delta)
                                flash()
                            }
                            .onEnded { _ in dragging = false; scheduleHide() }
                    )
                    .onHover { h in hovering = h; if h { flash() } else { scheduleHide() } }
                    .onChange(of: metrics.offsetY) { _ in flash() }
            }
        }
        .allowsHitTesting(metrics.scrollable)
    }

    private var thumbColor: Color {
        if dragging { return Palette.textSecondary.opacity(0.65) }
        if hovering { return Palette.textTertiary.opacity(0.7) }
        return Palette.textTertiary.opacity(0.45)
    }

    /// 滚动 / 悬停 / 拖拽时淡入，并重排空闲淡出。
    private func flash() {
        if !visible { visible = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !dragging, !hovering else { return }
        let work = DispatchWorkItem { visible = false }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}
