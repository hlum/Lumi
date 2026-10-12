import ImagePlayground
import PhotosUI
import SwiftUI

/// Pictures, avatars, stickers and emoji made on the device with Apple's Image Playground, from words and an optional photo.
struct AICreateView: View {
    enum Kind: String, CaseIterable { case picture = "Picture", avatar = "Avatar", sticker = "Sticker", emoji = "Emoji" }
    @Environment(\.supportsImagePlayground) private var supported
    @State private var kind = Kind.picture
    @State private var concept = ""
    @State private var item: PhotosPickerItem?
    @State private var source: Image?
    @State private var show = false
    @State private var result: UIImage?
    @State private var resultData: Data?
    @State private var message: LocalizedStringKey?
    @State private var editRoute: EditorRoute?

    static let prompts: [Kind: [String]] = [
        .picture: ["Animation", "Illustration", "Sketch"], .avatar: ["Cartoon", "Watercolour", "Pixel art"], .sticker: ["Cute cat", "Happy sun", "Coffee cup"], .emoji: ["Sleepy", "Party", "In love"],
    ]

    var body: some View {
        ToolScaffold(title: "Create") {
            Group {
                if let result { Image(uiImage: result).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous)) }
                else { VStack(spacing: 10) { Image(systemName: "sparkles").font(.system(size: 40)); Text(supported ? "Describe it, or start from a photo" : "Image Playground isn't available on this iPhone").font(LumiFont.headline()).multilineTextAlignment(.center) }.foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        } panel: {
            LumiSegmented(items: Kind.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $kind, height: 40)
            TextField("Describe it", text: $concept).lumiField()
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(Self.prompts[kind] ?? [], id: \.self) { p in LumiChip(title: LocalizedStringKey(p)) { concept = p } } } }
            HStack(spacing: 10) {
                PhotosPicker(selection: $item, matching: .images) { Label(source == nil ? "Start from a photo" : "Change photo", systemImage: "photo").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.text).background(Capsule().fill(LumiColor.well)) }
                LumiPrimaryButton(title: result == nil ? "Create" : "Make another", symbol: "sparkles", disabled: !supported || (concept.trimmingCharacters(in: .whitespaces).isEmpty && source == nil)) { show = true }
            }
            if result != nil, let data = resultData {
                HStack(spacing: 10) {
                    LumiPrimaryButton(title: "Save", symbol: "square.and.arrow.down") { Task { message = (try? await LibraryPhotoSaver().save(data)) != nil ? "Saved to Photos" : "Couldn't save" } }
                    LumiPrimaryButton(title: "Edit", symbol: "slider.horizontal.3") { editRoute = EditorRoute(data: data, tool: nil) }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
        }
        .imagePlaygroundSheet(isPresented: $show, concept: concept.isEmpty ? (Self.prompts[kind]?.first ?? "") : concept, sourceImage: source) { url in
            if let d = try? Data(contentsOf: url), let ui = UIImage(data: d) { result = ui; resultData = d }
        }
        .navigationDestination(item: $editRoute) { r in EditorView(initial: r.data, startTool: r.tool) }
        .onChange(of: item) { _, new in Task { if let d = try? await new?.loadTransferable(type: Data.self), let ui = UIImage(data: d) { source = Image(uiImage: ui) } } }
    }
}
