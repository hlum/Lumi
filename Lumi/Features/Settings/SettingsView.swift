import SwiftUI

struct SettingsView: View {
    @State private var format = AppPrefs.format
    @State private var quality = AppPrefs.quality
    @State private var maxSide = AppPrefs.maxLongSide
    @State private var appearance = AppPrefs.appearance
    @State private var cache = CacheManager.standard
    @State private var cacheBytes = 0
    @State private var cleared = false
    @AppStorage("look.appearance") private var appearanceStored = AppPrefs.Appearance.system.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(LumiFont.largeTitle()).padding(.top, 8)

                group("Saving") {
                    LumiSegmented(items: ImageFormat.allCases.map { ($0, LocalizedStringKey($0.rawValue.uppercased())) }, selection: $format, height: 40)
                    if format != .png { LumiSliderRow(title: "Quality", value: $quality, range: 0.3...1, defaultValue: 0.9, onEnd: {}) }
                    LumiSegmented(items: [(0, LocalizedStringKey("Full size")), (4096, LocalizedStringKey("4096")), (2048, LocalizedStringKey("2048")), (1080, LocalizedStringKey("1080"))], selection: $maxSide, height: 40)
                }
                group("Look") {
                    LumiSegmented(items: AppPrefs.Appearance.allCases.map { ($0, LocalizedStringKey($0.rawValue.capitalized)) }, selection: $appearance, height: 40)
                }
                group("System") {
                    row("Language", value: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                }
                group("Activity and storage") {
                    NavigationLink { RecentTasksView() } label: { navRow("Recent tasks") }.buttonStyle(.plain)
                    NavigationLink { ModelsView() } label: { navRow("AI models") }.buttonStyle(.plain)
                    row("Clear cache", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)) { cache.clearAll(); cacheBytes = cache.total; cleared = true }
                }
                group("About") {
                    NavigationLink { CreditsView() } label: { navRow("Credits") }.buttonStyle(.plain)
                    NavigationLink { PrivacyView() } label: { navRow("Privacy") }.buttonStyle(.plain)
                    HStack { Text("Version").font(LumiFont.body()); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-").foregroundStyle(LumiColor.textSecondary) }.padding(.horizontal, 16).frame(minHeight: 52)
                }
            }
            .padding(.horizontal, LumiShape.margin).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { cacheBytes = cache.total }
        .onChange(of: format) { _, v in AppPrefs.format = v }
        .onChange(of: quality) { _, v in AppPrefs.quality = v }
        .onChange(of: maxSide) { _, v in AppPrefs.maxLongSide = v }
        .onChange(of: appearance) { _, v in AppPrefs.appearance = v; appearanceStored = v.rawValue }
    }

    private func group<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(LumiFont.section())
            VStack(spacing: 8) { content() }.padding(12).background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
        }
    }

    private func row(_ title: LocalizedStringKey, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title).font(LumiFont.body()); Spacer(); Text(value).foregroundStyle(LumiColor.textSecondary); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(LumiColor.textSecondary) }.padding(.horizontal, 4).frame(minHeight: 48) }.buttonStyle(.plain)
    }

    private func navRow(_ title: LocalizedStringKey) -> some View {
        HStack { Text(title).font(LumiFont.body()).foregroundStyle(LumiColor.text); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(LumiColor.textSecondary) }.padding(.horizontal, 4).frame(minHeight: 48)
    }
}

struct RecentTasksView: View {
    var body: some View {
        let jobs = JobCenter.shared.jobs
        List {
            if jobs.isEmpty { Text("Nothing running. Long jobs show up here.").foregroundStyle(.secondary) }
            ForEach(jobs) { j in
                HStack { Text(j.title); Spacer(); ProgressView(value: j.progress).frame(width: 80) }
            }
        }.navigationTitle("Recent tasks")
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your photos stay on your iPhone.").font(LumiFont.title())
                Text("Every edit, including the AI tools, runs on the device. Lumi has no account, no tracking and no ads, and it sends nothing about you or your photos anywhere.").font(LumiFont.body())
                Text("It asks for your photo library to open and save pictures, the camera to take them, and the microphone only when you record a voice-over.").font(LumiFont.body())
            }.padding(LumiShape.margin)
        }.background(LumiColor.ground.ignoresSafeArea()).navigationTitle("Privacy")
    }
}
