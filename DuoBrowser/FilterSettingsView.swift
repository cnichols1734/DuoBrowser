import SwiftUI

struct FilterSettingsView: View {
    @ObservedObject private var filters = FilterCatalog.shared
    var body: some View {
        Form {
            Section {
                Label("EasyList", systemImage: "checkmark").accessibilityLabel("EasyList, included")
                Label("EasyPrivacy", systemImage: "checkmark").accessibilityLabel("EasyPrivacy, included")
            } header: { Text("Ads & Trackers") } footer: {
                Text("Maintained filters block ad and tracking requests and hide supported ad elements. Some ads, including complex video ads, may still appear.")
            }
            Section {
                Toggle("Hide Cookie Notices", isOn: $filters.hideCookieNotices)
            } footer: {
                Text("Uses EasyList Cookie List. Hiding a notice doesn’t choose consent for you. Turn this off if a website needs its consent controls. Reload when you’re ready to apply visual changes.")
            }
            Section {
                Toggle("Automatic Updates", isOn: $filters.automaticUpdates)
                if let date = filters.updatedAt {
                    LabeledContent("Filters Updated") { Text(date, style: .date).foregroundStyle(.secondary) }
                }
                Button {
                    Task { await filters.update() }
                } label: {
                    HStack {
                        Text(filters.updating ? "Updating Filters…" : "Update Now")
                        Spacer()
                        if filters.updating { ProgressView() }
                    }
                }.disabled(filters.updating)
                if let message = filters.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Updates") } footer: {
                Text("Updates download public filter lists without your browsing history or cookies. If an update fails, the last working filters stay active.")
            }
            Section {
                NavigationLink("Filter Credits & Licenses") { FilterCreditsView() }
            }
        }
        .navigationTitle("Filter Lists")
        .navigationBarTitleDisplayMode(.inline)
        .task { _ = await filters.rules() }
    }
}

private struct FilterCreditsView: View {
    var body: some View {
        List {
            Section("EasyList & EasyPrivacy") {
                Text("The EasyList authors (easylist.to). Distributed under Creative Commons Attribution-ShareAlike 3.0 Unported. DuoBrowser converts supported rules into WebKit’s declarative format; unsupported rules are omitted. Converted filter data retains this license.")
                Link("Source & License Options", destination: URL(string: "https://easylist.to/pages/licence.html")!)
                license("Attribution-ShareAlike 3.0", file: "CC-BY-SA-3.0")
            }
            Section("EasyList Cookie List") {
                Text("The EasyList authors and Fanboy. Distributed under Creative Commons Attribution 3.0 Unported, as specified in the list header. Converted into supported declarative WebKit rules.")
                Link("Original Filter List", destination: URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!)
                license("Attribution 3.0", file: "CC-BY-3.0")
            }
            Section {
                Text("DuoBrowser’s original application code remains MIT-licensed. Filter data is separately licensed. No affiliation or endorsement is implied.")
                Link("Filter Sources & Conversion", destination: URL(string: "https://github.com/cnichols1734/DuoBrowser/tree/main/DuoBrowser/FilterLists")!)
            }
        }.navigationTitle("Filter Credits").navigationBarTitleDisplayMode(.inline)
    }
    private func license(_ title: String, file: String) -> some View {
        NavigationLink(title) {
            ScrollView {
                Text(Bundle.main.url(forResource: file, withExtension: "txt", subdirectory: "FilterLists")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "The license is also included with the filter sources.")
                    .font(.footnote).textSelection(.enabled).padding()
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        }
    }
}
