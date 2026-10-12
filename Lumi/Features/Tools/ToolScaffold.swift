import SwiftUI
import UIKit

/// The shape every tool screen shares: ground, a top bar with back and a title, content above and a white panel below.
struct ToolScaffold<Content: View, Panel: View>: View {
    var title: LocalizedStringKey
    var trailing: AnyView?
    @ViewBuilder var content: Content
    @ViewBuilder var panel: Panel
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey, trailing: AnyView? = nil, @ViewBuilder content: () -> Content, @ViewBuilder panel: () -> Panel) {
        self.title = title; self.trailing = trailing; self.content = content(); self.panel = panel()
    }

    var body: some View {
        ZStack {
            LumiColor.ground.ignoresSafeArea()
            VStack(spacing: 12) {
                HStack {
                    LumiIconButton(symbol: "chevron.left", label: "Back", raised: true) { dismiss() }
                    Spacer()
                    Text(title).font(LumiFont.headline())
                    Spacer()
                    if let trailing { trailing } else { Color.clear.frame(width: 44, height: 44) }
                }
                .padding(.horizontal, 14).padding(.top, 4)
                content.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, LumiShape.margin)
                LumiPanel { VStack(spacing: 12) { panel }.padding(.bottom, 10) }
            }
        }
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
    }
}

/// A photo-shaped frame for showing a CIImage.
struct CIImageFrame: View {
    var image: CIImage?
    var placeholder: LocalizedStringKey = "Choose a photo"
    var body: some View {
        Group {
            if let image { MetalPreviewView(image: image).aspectRatio(max(image.extent.width, 1) / max(image.extent.height, 1), contentMode: .fit) }
            else { VStack(spacing: 10) { Image(systemName: "photo").font(.system(size: 40)); Text(placeholder).font(LumiFont.headline()) }.foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .clipShape(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous))
    }
}

/// A primary action pill: dark, full width.
struct LumiPrimaryButton: View {
    var title: LocalizedStringKey
    var symbol: String?
    var disabled = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { if let symbol { Image(systemName: symbol) }; Text(title) }.font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(LumiColor.onSelectedPill).background(Capsule().fill(LumiColor.selectedPill))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}
