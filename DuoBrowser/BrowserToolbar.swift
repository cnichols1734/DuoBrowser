import SwiftUI

struct BrowserToolbar: View {
    @State private var showingRecentlyClosed = false
    @State private var showingPageControls = false
    @State private var pendingPageAction: PageControlsRequest?
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var chrome: BrowserChromeState
    @Binding var input: String
    @Binding var showingAddress: Bool
    let keyboardVisible: Bool
    let bottomSafeArea: CGFloat
    let accessibilityExpanded: Bool
    @State private var showingProtection = false
    @State private var websiteSettings: WebsiteSettingsScope?
    @State private var showingSettings = false
    @State private var savingPage: LibraryEntry?
    @State private var showingDownloads = false
    @State private var setupAfterSettings = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var textLineHeight = 20.0
    @ScaledMetric(relativeTo: .body) private var addressFont = 17.0
    @ScaledMetric(relativeTo: .caption) private var statusLineHeight = 15.0
    @AccessibilityFocusState private var addressFocused: Bool
    @AccessibilityFocusState private var pageControlsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var keepExpanded: Bool {
        showingAddress || keyboardVisible || accessibilityExpanded || session.showingTabs || showingPageControls
    }
    private var progress: CGFloat {
        keepExpanded || browser.errorMessage != nil ? 0 : chrome.progress
    }

    private var statusText: String {
        [browser.isPrivate ? "Private" : nil, browser.transportLabel.isEmpty ? nil : "Not Secure"].compactMap { $0 }.joined(separator: " · ")
    }
    private var addressRowHeight: CGFloat {
        max(52, textLineHeight + 16) + (statusText.isEmpty || showingAddress ? 0 : statusLineHeight + 4)
    }
    private var toolbarHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? addressRowHeight + 60 : 52 }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { accessibleControls }
            else { compactControls }
        }
        .onChange(of: toolbarHeight, initial: true) { _, height in browser.chrome.expandedHeight = height }
        .onChange(of: keepExpanded, initial: true) { _, value in browser.keepControlsExpanded = value }
        .sheet(isPresented: $showingPageControls, onDismiss: finishPageAction) {
            PageControlsView(session: session, browser: browser) { action in
                pendingPageAction = PageControlsRequest(action: action, browser: browser)
                showingPageControls = false
            }
        }
        .sheet(isPresented: $showingRecentlyClosed) { RecentlyClosedView(session: session) }
        .sheet(item: $savingPage, onDismiss: { pageControlsFocused = true }) { SavePageView(session: session, browser: browser, entry: $0) }
        .sheet(isPresented: $showingDownloads, onDismiss: { pageControlsFocused = true }) { DownloadsView(manager: browser.downloads) }
        .sheet(isPresented: $showingSettings, onDismiss: {
            if setupAfterSettings { setupAfterSettings = false; session.setup.reopen(); session.showingSetup = true }
            else { pageControlsFocused = true }
        }) {
            BrowserLinkSettings(session: session, routing: session.redditLinks, onSetup: {
                setupAfterSettings = true; showingSettings = false
            })
        }
        .sheet(isPresented: $showingProtection, onDismiss: { pageControlsFocused = true }) { BrowserProtectionView(session: session, browser: browser) }
        .sheet(item: $websiteSettings, onDismiss: { pageControlsFocused = true }) { scope in WebsiteSettingsView(session: session, browser: browser, scope: scope) }
        .fullScreenCover(item: $browser.readerArticle, onDismiss: { pageControlsFocused = true }) { ReaderView(article: $0, sourceBrowser: browser) }
        .onChange(of: browser.address) { _, value in if !showingAddress { input = value } }

    }

    private var compactControls: some View {
        GeometryReader { geometry in
            let width = min(620, max(240, geometry.size.width - 24))
            let expandedWidth = width - 124
            let compactWidth = min(expandedWidth, max(110, CGFloat((browser.transportLabel + browser.privateLabel + browser.siteName).count) * 7 + 32))
            let p = progress
            let capsuleWidth = expandedWidth + (compactWidth - expandedWidth) * p
            GlassEffectContainer(spacing: 8) {
                ZStack {
                    if p < 0.5 {
                        Button { browser.webView.goBack() } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 21, weight: .medium))
                                .frame(width: 52, height: 52)
                        }
                        .disabled(!browser.canGoBack)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .offset(x: -(width - 52) / 2 * (1 - 0.1 * p))
                        .opacity(max(0, 1 - p * 2))
                        .scaleEffect(1 - 0.2 * p)
                        .allowsHitTesting(p < 0.1)
                        .accessibilityHidden(p > 0.1)
                        .accessibilitySortPriority(5)
                        .accessibilityLabel("Back")
                        .modifier(BackHistoryMenu(browser: browser))
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }

                    ZStack {
                        Group {
                            Button {
                                if p > 0.1 { browser.revealControls() }
                                else { input = browser.address; showingAddress = true }
                            } label: {
                                Text(browser.transportLabel + browser.privateLabel + browser.siteName)
                                    .font(.system(size: addressFont - 5 * p, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: max(40, capsuleWidth - 88 * (1 - p)), height: 44)
                                    .contentShape(Rectangle())
                            }
                            .modifier(TabSwipeGestureModifier(session: session, enabled: !keepExpanded))
                            .accessibilityAction(named: "Next Tab") { session.switchAdjacentTab(1) }
                            .accessibilityAction(named: "Previous Tab") { session.switchAdjacentTab(-1) }
                            .accessibilityFocused($addressFocused)
                            .accessibilitySortPriority(3)
                            .accessibilityLabel(p > 0.1 ? "Show browser controls for \(browser.privateLabel)\(browser.siteName)" : "Address, \(browser.transportLabel)\(browser.privateLabel)\(browser.siteName)")
                            HStack(spacing: 0) {
                                pageMenu.frame(width: 44, height: 44).accessibilitySortPriority(4)
                                Spacer(minLength: 0)
                                Button {
                                    if browser.isLoading { browser.webView.stopLoading() }
                                    else { browser.webView.reload() }
                                } label: {
                                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilitySortPriority(2)
                                .accessibilityLabel(browser.isLoading ? "Stop loading" : "Reload")
                            }
                            .font(.system(size: 19))
                            .opacity(max(0, 1 - p * 2))
                            .allowsHitTesting(p < 0.1)
                            .accessibilityHidden(p > 0.1)
                        }
                    }
                    .frame(width: capsuleWidth, height: 52 - 22 * p)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .overlay(alignment: .bottom) {
                        if browser.isLoading && p < 0.1 {
                            ProgressView(value: browser.progress)
                                .padding(.horizontal, 22)
                                .padding(.bottom, 4)
                                .accessibilityLabel("Page loading")
                        }
                    }

                    if p < 0.5 {
                        Button {
                            showingAddress = false
                            session.showTabs()
                        } label: {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 21, weight: .medium))
                                .frame(width: 52, height: 52)
                        }
                        .glassEffect(.regular.interactive(), in: Circle())
                        .offset(x: (width - 52) / 2 * (1 - 0.1 * p))
                        .opacity(max(0, 1 - p * 2))
                        .scaleEffect(1 - 0.2 * p)
                        .allowsHitTesting(p < 0.1)
                        .accessibilityHidden(p > 0.1)
                        .accessibilitySortPriority(1)
                        .accessibilityLabel("Tabs, \(session.visibleTabs.count) open")
                        .contextMenu {
                            tabActions
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: geometry.size.width, height: 52, alignment: .center)
                // Expanded controls sit slightly lower; the compact pill lands 8pt from the screen edge.
                // Keep the keyboard's own safe-area positioning intact while editing.
                .offset(y: keyboardVisible ? 0 : min(12, bottomSafeArea)
                        + (bottomSafeArea + 11 - min(12, bottomSafeArea)) * p)
                .animation(reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0), value: p)
            }
        }
        .frame(height: 52)
    }

    private func endEditing() { showingAddress = false; addressFocused = true }

    private var accessibleControls: some View {
        VStack(spacing: 8) {
            Group {
                Group {
                    Button {
                        input = browser.address; showingAddress = true
                    } label: {
                        VStack(spacing: 4) {
                            Text(browser.siteName).font(.body.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            if !statusText.isEmpty { Text(statusText).font(.caption).lineLimit(1) }
                        }
                        .frame(maxWidth: .infinity, minHeight: addressRowHeight)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Address, \(browser.transportLabel)\(browser.privateLabel)\(browser.siteName)")
                    .accessibilityHint("Edit the website address or search")
                    .accessibilityFocused($addressFocused)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: addressRowHeight)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
            HStack {
                Button { browser.webView.goBack() } label: {
                    Image(systemName: "chevron.backward").frame(width: 52, height: 52)
                }.disabled(!browser.canGoBack).accessibilityLabel("Back")
                    .modifier(BackHistoryMenu(browser: browser))
                Spacer(minLength: 0)
                pageMenu.frame(width: 52, height: 52)
                Spacer(minLength: 0)
                Button { if browser.isLoading { browser.webView.stopLoading() } else { browser.webView.reload() } } label: {
                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise").frame(width: 52, height: 52)
                }.accessibilityLabel(browser.isLoading ? "Stop loading" : "Reload")
                Spacer(minLength: 0)
                Button { endEditing(); session.showTabs() } label: {
                    Image(systemName: "square.on.square").frame(width: 52, height: 52)
                }.accessibilityLabel("Tabs, \(session.visibleTabs.count) open")
                    .contextMenu { tabActions }
                    .accessibilityAction(named: "Next Tab") { session.switchAdjacentTab(1) }
                    .accessibilityAction(named: "Previous Tab") { session.switchAdjacentTab(-1) }
            }
            .font(.system(size: 23, weight: .medium))
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .frame(height: toolbarHeight)
    }

    @ViewBuilder private var tabActions: some View {
        Button("New Tab", systemImage: "plus") { session.newTab() }
        Button("Previous Tab", systemImage: "chevron.left") { session.switchAdjacentTab(-1) }
            .disabled(session.visibleTabs.first?.id == session.selectedID)
        Button("Next Tab", systemImage: "chevron.right") { session.switchAdjacentTab(1) }
            .disabled(session.visibleTabs.last?.id == session.selectedID)
        if !session.privateMode {
            Button("Recently Closed", systemImage: "clock.arrow.circlepath") { showingRecentlyClosed = true }
        }
        Button("Close This Tab", systemImage: "xmark") { session.close(browser.id) }
    }

    private var pageMenu: some View {
        Button {
            pendingPageAction = nil
            browser.revealControls()
            showingPageControls = true
        } label: {
            DownloadPageOptionsSymbol(manager: browser.downloads)
        }
        .accessibilityLabel("Page options")
        .accessibilityHint("Page actions, website controls, and browser settings")
        .accessibilityFocused($pageControlsFocused)
    }

    /// Present the next surface only after the controls sheet has finished dismissing.
    private func finishPageAction() {
        let request = pendingPageAction
        pendingPageAction = nil
        guard let request, session.selectedID == browser.id, request.matches(browser) else {
            pageControlsFocused = true
            return
        }
        switch request.action {
        case .share:
            if let url = browser.restorationURL { browser.presentation.share(url) }
        case .save:
            if let url = browser.restorationURL { savingPage = LibraryEntry(address: url.absoluteString, title: browser.title) }
        case .find:
            browser.loadedWebView?.findInteraction?.presentFindNavigator(showingReplace: false)
        case .reader:
            browser.openReader()
        case .protection:
            showingProtection = true
        case .websiteSettings:
            websiteSettings = WebsiteSettingsScope(browser: browser)
        case .newTab:
            session.newTab()
        case .forward:
            browser.loadedWebView?.goForward()
        case .pin:
            session.togglePin(browser)
            addressFocused = true
        case .workspaces:
            session.showingWorkspaces = true
        case .library:
            session.showingLibrary = true
        case .downloads:
            showingDownloads = true
        case .settings:
            showingSettings = true
        #if DEBUG
        case .regions:
            session.showRegions.toggle()
        case .fixture:
            browser.loadFixture()
        #endif
        }
    }

}


struct BrowserPrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Your browsing data") {
                    Text("DuoBrowser has no app analytics, advertising SDKs or tracking service. History, bookmarks, settings and normal tabs are stored in the app on your device and may be included in system backups.")
                    Text("Delete history, bookmarks, folders, and Reading List items in Library. Clearing history does not clear cookies. Manage normal website cookies, storage and caches in Settings → Clear Browsing Data or Website Data. Remove a wallpaper in Tabs → Tab options → Tab Appearance.")
                }
                Section("Private browsing") {
                    Text("Private tabs use a separate temporary website-data store. Private history, tabs and previews are not saved to the normal browsing archive. Closing all private tabs clears that session. Bookmarks you explicitly save and files you export remain until you delete them. Normal downloads are kept on this device until you remove them from Downloads; private downloads are removed when all private tabs close. Private mode does not hide your network traffic.")
                }
                Section("Websites and search") {
                    Text("Websites receive normal browsing requests. Your chosen search engine receives searches. With Google selected and online suggestions enabled, Google receives plain keywords typed in normal tabs. Private tabs do not request typing suggestions. Shortcut icons load from site home pages and their icon hosts without your saved page paths, cookies or credentials. These services have their own privacy policies.")
                }
                Section("Photos and permissions") {
                    Text("Only a wallpaper photo you choose is imported, resized and saved locally. Website camera, microphone and location requests use system permission prompts. No page content is sent to an AI service.")
                }
                Section("Beta testing and support") {
                    Text("Apple handles TestFlight diagnostics and feedback according to its policies. If you contact support, we receive the information you choose to send. Do not include passwords or private browsing data.")
                    Link("Full Privacy Policy", destination: URL(string: "https://github.com/cnichols1734/DuoBrowser/blob/main/PRIVACY.md")!)
                    Link("Contact Support", destination: URL(string: "mailto:chrisnichols17@gmail.com")!)
                }
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
