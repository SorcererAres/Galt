import SwiftUI

/// 全应用统一的交互态按钮样式。
/// 四态一律走 `Palette.stateHover / stateSelected / statePressed`（前景色半透明，
/// 相对对比、跨底色稳定），保证 hover / selected / pressed / default 在所有组件一致。
///
/// SwiftUI 的 `ButtonStyle` 只暴露 `isPressed`，hover 需在 `makeBody` 内用 `@State` + `onHover` 自管。

// MARK: - 行 / 列表 / 分段

/// 整行点击区（侧栏行、供应商列表、分段控件）。
/// 层级：按下 > 选中 > 悬停 > 默认。选中底可由外部绘制（如侧栏 matchedGeometry 滑块），
/// 此时本样式只补 hover / pressed，并在选中时抑制 hover 以免叠色。
struct RowButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var cornerRadius: CGFloat = ConsoleDesign.sidebarRowRadius
    /// 选中底是否由外部绘制；true 时本样式不画选中底。
    var selectionDrawnExternally: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration,
             isSelected: isSelected,
             cornerRadius: cornerRadius,
             selectionDrawnExternally: selectionDrawnExternally)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        let cornerRadius: CGFloat
        let selectionDrawnExternally: Bool
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fill: Color {
            if configuration.isPressed { return Palette.statePressed }
            if isSelected { return selectionDrawnExternally ? .clear : Palette.stateSelected }
            if hovering { return Palette.stateHover }
            return .clear
        }

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

// MARK: - 图标按钮

/// 图标 / 紧凑按钮（复制、删除、搜索、关闭、×）。
/// 默认透明，悬停 / 按下显示圆角底 + 轻微缩放，扩大可点击感与命中区。
struct IconButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6
    var padding: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, cornerRadius: cornerRadius, padding: padding)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let padding: CGFloat
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fill: Color {
            if configuration.isPressed { return Palette.statePressed }
            if hovering { return Palette.stateHover }
            return .clear
        }

        var body: some View {
            configuration.label
                .padding(padding)
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

// MARK: - 实心主按钮

/// 实心强调按钮（「添加词语」等）。悬停提亮 → primaryHover，按下压暗 → primaryActive。
struct FilledButtonStyle: ButtonStyle {
    var fill: Color = Palette.primary
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, fill: fill, cornerRadius: cornerRadius)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let fill: Color
        let cornerRadius: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var bg: Color {
            if configuration.isPressed { return Palette.primaryActive }
            if hovering { return Palette.primaryHover }
            return fill
        }

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(bg))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { if isEnabled { hovering = $0 } }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

// MARK: - 描边次按钮

/// 描边次按钮（「下载」「验证」「获取模型」）。默认透明描边，悬停 / 按下加状态层底。
struct OutlineButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var border: Color = Palette.borderDefault

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, cornerRadius: cornerRadius, border: border)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let cornerRadius: CGFloat
        let border: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fill: Color {
            if configuration.isPressed { return Palette.statePressed }
            if hovering { return Palette.stateHover }
            return .clear
        }

        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(border, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { if isEnabled { hovering = $0 } }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

// MARK: - 通用按下反馈

/// 最轻量的按下反馈（按下压暗 + 微缩），不画任何底，供已自带形状 / 底色的按钮叠加
/// （如 HUD 圆形按钮：自身已有圆底与 hover 透明度，仅缺 pressed）。
struct PressableButtonStyle: ButtonStyle {
    var pressedOpacity: Double = 0.66
    var pressedScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, pressedOpacity: pressedOpacity, pressedScale: pressedScale)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let pressedOpacity: Double
        let pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? pressedOpacity : 1)
                .scaleEffect(configuration.isPressed ? pressedScale : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

// MARK: - 自定义下拉（替代系统 Picker）

/// 下拉选项（值统一为 String，与各 @AppStorage 绑定一致）。
struct DropdownOption: Identifiable {
    let value: String
    let title: String
    var id: String { value }
}

/// 替代系统 `Picker(.menu)` 的自定义下拉（对照 Figma：28 高 / 圆角 8 / 描边盒 /
/// 12px 文字 / 右侧单个下箭头 / 宽度随内容自适应）。用 `Menu` 承载选项，
/// label 套用 `HoverBorderBox`，与表单框 / 按钮共用同一套 hover 语言；选中项在菜单内打勾。
struct DropdownPicker: View {
    @Binding var selection: String
    let options: [DropdownOption]
    /// 可选最小宽度；默认随内容自适应（贴合设计稿的紧凑右对齐盒）。
    var minWidth: CGFloat? = nil

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options) { opt in
                Button {
                    selection = opt.value
                } label: {
                    if opt.value == selection {
                        Label(opt.title, systemImage: "checkmark")
                    } else {
                        Text(opt.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(currentTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 12, height: 12)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .frame(minWidth: minWidth, alignment: .leading)
            .frame(height: 28)
            .modifier(HoverBorderBox(idleBorder: Palette.borderDefault))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - 描边盒 hover（自定义下拉 / 只读字段）

/// 给「带描边的盒子」（自定义 Menu 下拉的 label 等）补 hover：
/// 默认 borderSubtle，悬停 borderHover + 极淡状态层底。系统 Picker / 文本框不用此修饰，
/// 它们各有自己的 focus / hover 逻辑。
struct HoverBorderBox: ViewModifier {
    var cornerRadius: CGFloat = 8
    var idleBorder: Color = Palette.borderSubtle
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(hovering ? Palette.stateHover : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(hovering ? Palette.borderHover : idleBorder, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - 文字链接按钮

/// 内联文字操作（「设为默认」「删除」「高级选项」）。无底，悬停 / 按下用透明度区分，轻量不喧宾。
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var opacity: Double {
            if configuration.isPressed { return 0.5 }
            if hovering { return 0.7 }
            return isEnabled ? 1 : 0.4
        }

        var body: some View {
            configuration.label
                .opacity(opacity)
                .contentShape(Rectangle())
                .onHover { if isEnabled { hovering = $0 } }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
