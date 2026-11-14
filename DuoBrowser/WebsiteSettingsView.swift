import SwiftUI

@MainActor
struct WebsiteSettingsScope: Identifiable {
    let id = UUID()
    let browserID: UUID
    let host: String?
    let isPrivate: Bool

    init(browser: BrowserModel) {
        browserID = browser.id
        host = browser.restorationURL?.host?.lowercased()
        isPrivate = browser.isPrivate
    }

    func matches(_ browser: BrowserModel) -> Bool {
        host != nil && browser.id == browserID && browser.isPrivate == isPrivate
            && browser.restorationURL?.host?.lowercased() == host
    }

    @discardableResult
    func set(_ value: Bool, for keyPath: ReferenceWritableKeyPath<BrowserModel, Bool>, on browser: BrowserModel) -> Bool {
        guard matches(browser) else { return false }
        guard browser[keyPath: keyPath] != value else { return true }
        browser[keyPath: keyPath] = value
        return true
    }
}

struct WebsiteSettingsView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    let scope: WebsiteSettingsScope
    @State private var showingProtection = false
    @AccessibilityFocusState private var protectionFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var protectionStatus: String {
        if !session.adBlockingEnabled { return "Off in Settings" }
        if !browser.blockAds { return "Off for this website" }
        return browser.blockingStatus
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(scope.host ?? "Website").font(.headline).textSelection(.enabled)
                    if scope.isPrivate { Label("Private Browsing", systemImage: "hand.raised").foregroundStyle(.secondary) }
                } footer: {
                    Text(scope.isPrivate ? "These settings apply only in private browsing and disappear when all private tabs close."
                         : "These settings are saved for this website. Other websites keep their own settings.")
                }
                Section {
                    Toggle("Original Layout", isOn: binding(\.originalPageLayout))
                    Toggle("Full-width Page", isOn: binding(\.fullWidthLayout))
                } header: { Text("Page Layout") } footer: {
                    Text("Original Layout turns off page adjustments around the camera. Full-width Page uses the available display width; turn it off for a conservative inset.")
                }
                Section {
                    Toggle("Desktop Website", isOn: binding(\.desktopSite))
                } footer: { Text("Changing Desktop Website reloads the page. Unsaved website input may be lost.") }
                Section {
                    Button { showingProtection = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Website Protection")
                                Text(protectionStatus).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary).accessibilityElement(children: .combine)
                    .accessibilityFocused($protectionFocused)
                }
            }
            .disabled(!scope.matches(browser))
            .navigationTitle("Website Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .sheet(isPresented: $showingProtection, onDismiss: { protectionFocused = true }) { BrowserProtectionView(session: session, browser: browser) }
        .onChange(of: browser.address) { _, _ in if !scope.matches(browser) { dismiss() } }
        .onChange(of: session.selectedID) { _, selected in if selected != scope.browserID { dismiss() } }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<BrowserModel, Bool>) -> Binding<Bool> {
        Binding(get: { browser[keyPath: keyPath] }, set: { scope.set($0, for: keyPath, on: browser) })
    }
}
