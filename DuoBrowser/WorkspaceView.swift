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
                                        Text(verbatim: workspace.name).font(.headline)
                                        Text("\(session.tabs.filter { !$0.isPrivate && $0.workspaceID == workspace.id }.count) open")
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

struct PeekView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if browser.isLoading { ProgressView(value: browser.progress).accessibilityLabel("Preview loading") }
                if let error = browser.errorMessage { Text(error).font(.callout).padding() }
                BrowserSurface(browser: browser, fullWidth: false, showRegions: false, reservesBrowserControls: false)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 32) {
                    Button { browser.webView.goBack() } label: { Image(systemName: "chevron.backward").frame(width: 48, height: 48) }
                        .disabled(!browser.canGoBack).accessibilityLabel("Back")
                    Button { browser.webView.reload() } label: { Image(systemName: "arrow.clockwise").frame(width: 48, height: 48) }
                        .accessibilityLabel("Reload")
                    Button { browser.webView.goForward() } label: { Image(systemName: "chevron.forward").frame(width: 48, height: 48) }
                        .disabled(!browser.canGoForward).accessibilityLabel("Forward")
                }
                .font(.title3).buttonStyle(.plain).padding(.horizontal, 16)
                .glassEffect(.regular.interactive(), in: Capsule()).padding(8)
            }
            .navigationTitle(browser.privateLabel + browser.siteName).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { session.dismissPeek() } }
                ToolbarItem(placement: .confirmationAction) { Button("Keep as Tab") { session.keepPeek() } }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
