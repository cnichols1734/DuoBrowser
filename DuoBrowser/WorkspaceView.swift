import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editing: Workspace?
    @State private var showName = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(session.workspaces) { workspace in
                        HStack {
                            Button {
                                session.switchWorkspace(workspace.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.stack")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: workspace.name).font(.headline).lineLimit(2)
                                        Text("\(session.tabs.filter { !$0.isPrivate && $0.workspaceID == workspace.id }.count) tabs")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !session.privateMode && session.workspaceID == workspace.id { Image(systemName: "checkmark") }
                                }.frame(minHeight: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button("Rename") { editing = workspace; name = workspace.name; showName = true }
                                if workspace.id != Workspace.defaultID {
                                    Button("Remove Workspace (Keep Tabs)") { session.removeWorkspace(workspace.id) }
                                }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel("Options for \(workspace.name)")
                        }
                    }
                } footer: {
                    Text("Workspaces organize normal tabs and share website logins. Removing a workspace moves its tabs to your first workspace. Private tabs remain separate.")
                }
                Button("New Workspace", systemImage: "plus") { editing = nil; name = ""; showName = true }
                    .disabled(session.workspaces.count >= 20 || session.tabs.count >= 200)
            }
            .navigationTitle("Workspaces").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(editing == nil ? "New Workspace" : "Rename Workspace", isPresented: $showName) {
                TextField("Name", text: $name)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let editing { session.renameWorkspace(editing.id, to: name) }
                    else { session.createWorkspace(name); dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}


struct BrowserProtectionView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    private var host: String? { browser.restorationURL?.host }
    private var unavailable: Bool { browser.blockingStatus == "Protection unavailable" }
    private var title: String {
        guard host != nil else { return "Ready to protect" }
        if !browser.blockAds { return "Off for this website" }
        if unavailable { return "Protection unavailable" }
        if browser.blockingStatus == "Preparing protection" { return "Preparing protection" }
        return "Protection is on"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: unavailable ? "exclamationmark.shield" : browser.blockAds ? "checkmark.shield.fill" : "shield.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(unavailable ? Color.orange : browser.blockAds ? Color.green : Color.secondary)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(.title2.weight(.bold))
                            Text(host ?? "Open a website to manage its protection.")
                                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if host != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Block ads & trackers", isOn: $browser.blockAds)
                                .font(.body.weight(.semibold))
                            Text("Changes reload this page. Turn protection off if a website isn't working correctly.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(20).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What’s protected").font(.headline)
                        Text(unavailable ? "The blocking rules couldn't load. Browsing still works. Relaunch DuoBrowser to try again." :
                             "When enabled, blocks third-party requests to a bundled list of 19 advertising and tracking services. Some ads may still appear.")
                            .font(.body).foregroundStyle(.secondary)
                        Text("Protection runs on your device. No browsing reports or blocked-request logs are collected.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Website exceptions").font(.headline)
                            Spacer()
                            if browser.isPrivate { Text("Private session").font(.caption).foregroundStyle(.secondary) }
                        }
                        let exceptions = session.blockingExceptions(isPrivate: browser.isPrivate)
                        if exceptions.isEmpty {
                            Text("No exceptions. Protection is enabled by default on websites.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(exceptions, id: \.self) { exception in
                                HStack(spacing: 12) {
                                    Text(exception).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Button("Protect") { session.restoreBlocking(host: exception, isPrivate: browser.isPrivate) }
                                        .buttonStyle(.bordered).controlSize(.small)
                                        .accessibilityLabel("Turn protection on for \(exception)")
                                }.frame(minHeight: 44)
                                if exception != exceptions.last { Divider() }
                            }
                        }
                        if browser.isPrivate {
                            Text("Private exceptions disappear when you close all private tabs.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("Website protection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
}
