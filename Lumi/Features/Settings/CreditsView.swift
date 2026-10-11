import SwiftUI

struct CreditsView: View {
    let entries: [CreditEntry]

    init() {
        entries = (Bundle.main.url(forResource: "Credits", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap { try? Credits.decode($0) }) ?? []
    }

    var body: some View {
        List(entries.indices, id: \.self) { i in
            let e = entries[i]
            VStack(alignment: .leading, spacing: 4) {
                Text(e.title).font(.headline)
                Text(e.attribution).font(.subheadline)
                Text(e.license).font(.caption).foregroundStyle(.secondary)
                if let url = URL(string: e.licenseURL), !e.licenseURL.isEmpty { Link("License", destination: url).font(.caption) }
            }
        }
        .navigationTitle("Credits")
        .overlay { if entries.isEmpty { ContentUnavailableView("No credits", systemImage: "heart") } }
    }
}

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("Credits") { CreditsView() }
            Section("About") { LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-") }
        }
        .navigationTitle("Settings")
    }
}
