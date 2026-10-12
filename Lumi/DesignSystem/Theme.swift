import SwiftUI
import UIKit

/// "Lumi Daylight": light first, a full dark set, one accent, rounded type, pills for every control.
enum LumiColor {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let ground = dynamic(0xF4F4F6, 0x0E0E10)
    static let surface = dynamic(0xFFFFFF, 0x1C1C1F)
    static let well = dynamic(0xF4F4F6, 0x2A2A2E)           // inset areas inside a surface
    static let text = dynamic(0x17171A, 0xF4F4F6)
    static let textSecondary = dynamic(0x55555C, 0xA8A8B0)
    static let hairline = dynamic(0xE4E4E8, 0x34343A)
    static let accent = dynamic(0xFF7A45, 0xFF8A5C)           // fills; always carries `onAccent`
    static let onAccent = Color(uiColor: UIColor(hex: 0x1F1208))
    static let accentSoft = dynamic(0xFFE9DF, 0x3A2219)
    static let accentText = dynamic(0xC2410C, 0xFF9D74)      // accent-coloured text and icons
    static let selectedPill = dynamic(0x17171A, 0xF4F4F6)
    static let onSelectedPill = dynamic(0xFFFFFF, 0x17171A)
    static let destructive = dynamic(0xC8281C, 0xFF6B5E)
    static let track = dynamic(0xDADADF, 0x3C3C42)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum LumiFont {
    static func largeTitle() -> Font { .system(size: 34, weight: .heavy, design: .rounded) }
    static func title() -> Font { .system(size: 24, weight: .heavy, design: .rounded) }
    static func section() -> Font { .system(size: 21, weight: .heavy, design: .rounded) }
    static func headline() -> Font { .system(size: 17, weight: .bold, design: .rounded) }
    static func body() -> Font { .system(size: 17, weight: .medium, design: .rounded) }
    static func chip() -> Font { .system(size: 15, weight: .bold, design: .rounded) }
    static func caption() -> Font { .system(size: 13, weight: .semibold, design: .rounded) }
    static func tab() -> Font { .system(size: 11, weight: .bold, design: .rounded) }
}

enum LumiShape {
    static let photo: CGFloat = 28
    static let panel: CGFloat = 32
    static let tile: CGFloat = 22
    static let iconWell: CGFloat = 14
    static let margin: CGFloat = 18
    static let minTarget: CGFloat = 44
}

// MARK: components

/// 44 pt round button; `dark` is the confirm style.
struct LumiIconButton: View {
    var symbol: String
    var label: LocalizedStringKey
    var dark = false
    var raised = false                 // white with a soft shadow, for buttons floating over the ground
    var disabled = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .frame(width: LumiShape.minTarget, height: LumiShape.minTarget)
                .foregroundStyle(dark ? LumiColor.onSelectedPill : LumiColor.text)
                .background(Circle().fill(dark ? LumiColor.selectedPill : (raised ? LumiColor.surface : LumiColor.well)))
                .shadow(color: raised ? .black.opacity(0.08) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }
}

/// Outlined or accent-filled pill used for options and presets.
struct LumiChip: View {
    var title: LocalizedStringKey
    var selected = false
    var edited = false
    var symbol: String?
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
                if edited { Circle().fill(LumiColor.accent).frame(width: 7, height: 7).accessibilityLabel("Edited") }
            }
            .font(LumiFont.chip()).lineLimit(1)
            .padding(.horizontal, 14).frame(minHeight: LumiShape.minTarget)
            .foregroundStyle(selected ? LumiColor.onAccent : LumiColor.text)
            .background(Capsule().fill(selected ? LumiColor.accent : LumiColor.surface))
            .overlay(Capsule().strokeBorder(selected ? LumiColor.accent : LumiColor.hairline, lineWidth: 1.5))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Dark-selected segmented control in a pill well.
struct LumiSegmented<T: Hashable>: View {
    var items: [(T, LocalizedStringKey)]
    @Binding var selection: T
    var height: CGFloat = 44
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                let (value, title) = items[i]
                Button { selection = value } label: {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: height - 6)
                        .foregroundStyle(selection == value ? LumiColor.onSelectedPill : LumiColor.textSecondary)
                        .background(Capsule().fill(selection == value ? LumiColor.selectedPill : .clear))
                }
                .buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(LumiColor.well))
    }
}

/// A round tool button with a label under it; shows a value (e.g. "+30") instead of an icon when `value` is set.
struct LumiToolCircle: View {
    var symbol: String?
    var value: String?
    var title: LocalizedStringKey
    var selected = false
    var size: CGFloat = 54
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(selected ? LumiColor.accent : LumiColor.well)
                    if let value { Text(value).font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit() }
                    else if let symbol { Image(systemName: symbol).font(.system(size: 22, weight: .regular)) }
                }
                .frame(width: size, height: size)
                .foregroundStyle(selected ? LumiColor.onAccent : LumiColor.text)
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(minWidth: LumiShape.minTarget)
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Title, value readout and a slider in an inset well. Values show as -100...100 (or 0...100) like other editors; double tap the value to reset.
struct LumiSliderRow: View {
    var title: LocalizedStringKey
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var defaultValue: Double = 0
    var unit = 100.0                    // readout = value x unit (degrees use 1)
    var onEditing: (Bool) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(title).font(LumiFont.chip())
                Spacer()
                Text(readout).font(LumiFont.chip()).monospacedDigit()
                    .onTapGesture(count: 2) { value = defaultValue; onEnd() }
                    .accessibilityHidden(true)
            }
            Slider(value: $value, in: range) { onEditing($0); if !$0 { onEnd() } }
                .tint(LumiColor.accent)
                .accessibilityLabel(title).accessibilityValue(readout)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LumiColor.well))
    }
    private var readout: String {
        let v = Int((value * unit).rounded())
        return range.lowerBound < 0 && v > 0 ? "+\(v)" : "\(v)"
    }
}

/// White bottom sheet with the design's big top corners.
struct LumiPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, LumiShape.margin).padding(.top, 16)
            .frame(maxWidth: .infinity)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: LumiShape.panel, topTrailingRadius: LumiShape.panel, style: .continuous)
                    .fill(LumiColor.surface).shadow(color: .black.opacity(0.07), radius: 15, y: -5).ignoresSafeArea(edges: .bottom)
            )
    }
}

/// Cancel (x) on the left, title in the middle, apply (check) on the right.
struct LumiPanelHeader: View {
    var title: LocalizedStringKey
    var cancel: () -> Void
    var apply: () -> Void
    var body: some View {
        HStack {
            LumiIconButton(symbol: "xmark", label: "Cancel", action: cancel)
            Spacer()
            Text(title).font(LumiFont.headline())
            Spacer()
            LumiIconButton(symbol: "checkmark", label: "Apply", dark: true, action: apply)
        }
    }
}

// MARK: button style for the older panels

private struct LumiSelectedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues { var lumiSelected: Bool { get { self[LumiSelectedKey.self] } set { self[LumiSelectedKey.self] = newValue } } }
extension View { func lumiSelected(_ on: Bool) -> some View { environment(\.lumiSelected, on) } }

/// Pill button: outlined, accent-filled when selected, dark when prominent.
struct LumiButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.lumiSelected) private var selected
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = prominent ? LumiColor.selectedPill : (selected ? LumiColor.accent : LumiColor.surface)
        let ink: Color = prominent ? LumiColor.onSelectedPill : (selected ? LumiColor.onAccent : LumiColor.text)
        configuration.label
            .font(LumiFont.chip()).lineLimit(1)
            .padding(.horizontal, 14).frame(minHeight: LumiShape.minTarget)
            .foregroundStyle(ink)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(selected ? LumiColor.accent : (prominent ? .clear : LumiColor.hairline), lineWidth: 1.5))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

/// Text tabs with a dark selected pill, for the groups inside a tool (Face, Eyes, Nose...).
struct LumiCategoryTabs<T: Hashable>: View {
    var items: [(T, LocalizedStringKey)]
    @Binding var selection: T
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(items.indices, id: \.self) { i in
                    let (value, title) = items[i]
                    Button { selection = value } label: {
                        Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(selection == value ? LumiColor.onSelectedPill : LumiColor.textSecondary)
                            .background(Capsule().fill(selection == value ? LumiColor.selectedPill : .clear))
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
        }
    }
}

/// Colour dots to choose from; the chosen one gets a ring.
struct LumiSwatchRow: View {
    var colors: [(name: String, color: RGBA)]
    var selected: RGBA?
    var onPick: (RGBA) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(colors, id: \.name) { c in
                    Button { onPick(c.color) } label: {
                        Circle().fill(Color(red: c.color.r, green: c.color.g, blue: c.color.b)).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(LumiColor.hairline, lineWidth: 1))
                            .padding(3).overlay(Circle().strokeBorder(selected == c.color ? LumiColor.selectedPill : .clear, lineWidth: 2))
                            .frame(minWidth: LumiShape.minTarget, minHeight: LumiShape.minTarget)
                    }
                    .buttonStyle(.plain).accessibilityLabel(Text(LocalizedStringKey(c.name))).accessibilityAddTraits(selected == c.color ? .isSelected : [])
                }
            }
        }
    }
}

/// A labelled on/off row in an inset well.
struct LumiToggleRow: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(LumiFont.chip())
                if let subtitle { Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .tint(.green).padding(.horizontal, 14).frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumiColor.well))
    }
}
