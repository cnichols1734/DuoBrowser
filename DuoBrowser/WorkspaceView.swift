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
                                        let count = session.tabs.filter { !$0.isPrivate && $0.workspaceID == workspace.id }.count
                                        Text("\(count) \(count == 1 ? "tab" : "tabs")")
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
    @ObservedObject private var filters = FilterCatalog.shared
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var scope: WebsiteSettingsScope
    #if DEBUG
    var scopeDidChange: ((WebsiteSettingsScope, Bool, Binding<Bool>) -> Void)?
    #endif
    private var host: String? { scope.host }
    private var isCurrent: Bool { scope.matches(browser) && session.selectedID == scope.browserID }

    init(session: BrowserSession, browser: BrowserModel) {
        _session = ObservedObject(wrappedValue: session)
        _browser = ObservedObject(wrappedValue: browser)
        _scope = State(initialValue: WebsiteSettingsScope(browser: browser))
    }
    private var protected: Bool { session.adBlockingEnabled && browser.blockAds }
    private var unavailable: Bool { browser.blockingStatus == "Protection unavailable" }
    private var title: String {
        if !session.adBlockingEnabled { return "Off in Settings" }
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
                        Image(systemName: unavailable ? "exclamationmark.shield" : protected ? "checkmark.shield.fill" : "shield.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(unavailable ? Color.orange : protected ? Color.green : Color.secondary)
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title).font(.title2.weight(.bold))
                            Text(host ?? "Open a website to manage its protection.")
                                .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    if !session.adBlockingEnabled {
                        Text("Ad blocking is turned off for all tabs. Enable Block Ads & Trackers in Settings to use website protection.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if host != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Block ads & trackers on this site", isOn: protectionEnabled)
                                .disabled(!session.adBlockingEnabled)
                                .font(.body.weight(.semibold))
                            Text("Changes apply to new requests. Reload when you’re ready; anything you’ve typed stays in place until then.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Reload This Page", systemImage: "arrow.clockwise") {
                                guard isCurrent else { return }
                                browser.loadedWebView?.reload()
                                dismiss()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What’s protected").font(.headline)
                        Text(unavailable ? "The blocking rules couldn't load. Browsing still works. Relaunch DuoBrowser to try again." :
                             filters.usingFallback ? "Basic fallback protection is active. Update filters to restore EasyList and EasyPrivacy." :
                             "EasyList and EasyPrivacy block supported ad and tracking requests and hide ad elements. Filters update independently of app releases. Some ads may still appear.")
                            .font(.body).foregroundStyle(.secondary)
                        Text("Protection runs on your device. No browsing reports or blocked-request logs are collected.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    NavigationLink("Filter Lists & Updates") { FilterSettingsView() }
                        .frame(minHeight: 44)
                    NavigationLink("Other Blocking Apps") { OtherBlockingAppsView() }
                        .frame(minHeight: 44)
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Website exceptions").font(.headline)
                            Spacer()
                            if browser.isPrivate { Text("Private session").font(.caption).foregroundStyle(.secondary) }
                        }
                        let exceptions = session.blockingExceptions(isPrivate: browser.isPrivate)
                        if exceptions.isEmpty {
                            Text("No website exceptions. When ad blocking is on, protection applies by default.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(exceptions, id: \.self) { exception in
                                HStack(spacing: 12) {
                                    Text(exception).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Button("Protect") {
                                        guard isCurrent else { return }
                                        session.restoreBlocking(host: exception, isPrivate: scope.isPrivate)
                                    }
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
            .disabled(host != nil && !isCurrent)
            .navigationTitle("Website Protection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: browser.address) { _, _ in if host != nil && !scope.matches(browser) { dismiss() } }
        .onChange(of: session.selectedID) { _, selected in if selected != scope.browserID { dismiss() } }
        .presentationDragIndicator(.visible)
        #if DEBUG
        .background {
            ProtectionScopeProbe(scope: scope, isCurrent: isCurrent, binding: protectionEnabled, report: scopeDidChange)
                .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)
        }
        #endif
    }

    private var protectionEnabled: Binding<Bool> {
        Binding(get: { browser.blockAds }, set: { value in
            guard isCurrent else { return }
            scope.set(value, for: \.blockAds, on: browser)
        })
    }
}

#if DEBUG
/// Reports the scope of the actual rendered view, including state retained after root-view replacement.
private struct ProtectionScopeProbe: UIViewRepresentable {
    let scope: WebsiteSettingsScope
    let isCurrent: Bool
    let binding: Binding<Bool>
    let report: ((WebsiteSettingsScope, Bool, Binding<Bool>) -> Void)?
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { report?(scope, isCurrent, binding) }
    }
}
#endif
