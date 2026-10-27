import SwiftUI

struct BrowserToolbar: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var chrome: BrowserChromeState
    @Binding var input: String
    let keyboardVisible: Bool
    let bottomSafeArea: CGFloat
    let accessibilityExpanded: Bool
    @State private var showingAddress = false
    @FocusState private var editing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var keepExpanded: Bool {
        showingAddress || editing || keyboardVisible || accessibilityExpanded || session.showingTabs
    }
    private var progress: CGFloat {
        keepExpanded || browser.errorMessage != nil ? 0 : chrome.progress
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(620, max(240, geometry.size.width - 24))
            let expandedWidth = width - 124
            let compactWidth = min(expandedWidth, max(110, CGFloat(browser.siteName.count) * 7 + 32))
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
                        .accessibilityLabel("Back")
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }

                    ZStack {
                        if showingAddress {
                            TextField("Search or enter website", text: $input)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.webSearch)
                                .submitLabel(.go)
                                .focused($editing)
                                .onAppear { editing = true }
                                .padding(.horizontal, 14)
                                .onSubmit {
                                    editing = false
                                    showingAddress = false
                                    browser.navigate(to: input)
                                }
                                .accessibilityLabel("Website address or search")
                        } else {
                            Button {
                                if p > 0.1 { browser.revealControls() }
                                else { input = browser.address; showingAddress = true }
                            } label: {
                                Text(browser.siteName)
                                    .font(.system(size: 17 - 5 * p, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: max(40, capsuleWidth - 88 * (1 - p)), height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(p > 0.1 ? "Show browser controls for \(browser.siteName)" : "Address, \(browser.siteName)")
                            HStack(spacing: 0) {
                                pageMenu.frame(width: 44, height: 44)
                                Spacer(minLength: 0)
                                Button {
                                    if browser.isLoading { browser.webView.stopLoading() }
                                    else { browser.webView.reload() }
                                } label: {
                                    Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                                        .frame(width: 44, height: 44)
                                }
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
                            editing = false
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
                        .accessibilityLabel("Tabs, \(session.tabs.count) open")
                        .contextMenu {
                            Button("New Tab", systemImage: "plus") { session.newTab() }
                            Button("Close This Tab", systemImage: "xmark") { session.close(browser.id) }
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
        .onChange(of: keepExpanded, initial: true) { _, value in
            browser.keepControlsExpanded = value
        }
        .onChange(of: editing) { _, focused in
            if !focused { showingAddress = false }
        }
        .onChange(of: browser.address) { _, value in
            if !editing { input = value }
        }
    }

    private var pageMenu: some View {
        Menu {
            Button("New Tab", systemImage: "plus") { session.newTab() }
            Button("Forward", systemImage: "chevron.forward") { browser.webView.goForward() }
                .disabled(!browser.canGoForward)
            Toggle("Full-width page", isOn: $session.fullWidth)
            Toggle("Original page layout", isOn: $browser.originalPageLayout)
            Toggle("Show reserved regions", isOn: $session.showRegions)
            Button("Open test page", systemImage: "ruler") { browser.loadFixture() }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Page options")
    }
}
