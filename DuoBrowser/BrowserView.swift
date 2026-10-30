import SwiftUI
import UIKit
import WebKit
import Combine

struct BrowserView: View {
    @StateObject private var session = BrowserSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ActiveBrowserView(session: session, browser: session.selected, viewport: session.selected.viewport)
            .id(session.selectedID)
            .fullScreenCover(isPresented: $session.showingTabs) {
                TabOverview(session: session)
            }
            .sheet(isPresented: $session.showingLibrary) { BrowserLibrary(session: session) }
            .sheet(isPresented: $session.showingWorkspaces) { WorkspaceView(session: session) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.background() }
            }
    }
}

private struct ActiveBrowserView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var viewport: BrowserViewportState
    @State private var input = ""
    @State private var keyboardVisible = false
    @State private var showingSearch = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                BrowserSurface(browser: browser, fullWidth: browser.fullWidthLayout, showRegions: session.showRegions)
                    .ignoresSafeArea(.container)
                    .blur(radius: showingSearch ? 5 : 0)
                    .accessibilityHidden(showingSearch)
                    .allowsHitTesting(!showingSearch && !browser.showingStartPage)
                if browser.showingStartPage {
                    BrowserStartPage(session: session, browser: browser) { showingSearch = true }
                        .blur(radius: showingSearch ? 5 : 0)
                        .accessibilityHidden(showingSearch)
                        .allowsHitTesting(!showingSearch)
                }
                VStack(spacing: 8) {
                    if let error = browser.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.callout)
                            Button("Dismiss") { browser.errorMessage = nil }.frame(minHeight: 44)
                        }
                        .padding(12)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 12)
                    }
                    BrowserToolbar(session: session, browser: browser, chrome: browser.chrome,
                                   input: $input, showingAddress: $showingSearch, keyboardVisible: keyboardVisible,
                                   bottomSafeArea: geometry.safeAreaInsets.bottom,
                                   accessibilityExpanded: voiceOverEnabled || dynamicTypeSize.isAccessibilitySize)
                }
                .padding(.bottom, 8 + viewport.bottomControlLift)
                .opacity(showingSearch ? 0 : 1)
                .allowsHitTesting(!showingSearch)
                .accessibilityHidden(showingSearch)

                if showingSearch {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea(.container)
                        .onTapGesture { closeSearch() }
                        .accessibilityHidden(true)
                    BrowserSearch(session: session, browser: browser, query: $input,
                                  availableHeight: geometry.size.height, dismiss: closeSearch)
                        .padding(.horizontal, browser.fullWidthLayout ? 16 : max(16, max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)))
                        .padding(.bottom, 12 + (keyboardVisible ? 0 : viewport.bottomControlLift))
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }
            }
            // Only the bottom controls reclaim the horizontal camera-safe rail. Keep keyboard/bottom safety.
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: showingSearch)
        .statusBarHidden(!session.showSystemStatus)
        .onAppear { input = browser.address }
        .onChange(of: browser.errorMessage) { _, message in
            if voiceOverEnabled, let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
            browser.revealControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private func closeSearch() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        showingSearch = false
    }
}

struct BrowserSurface: UIViewRepresentable {
    let browser: BrowserModel
    let fullWidth: Bool
    let showRegions: Bool
    var reservesBrowserControls = true

    func makeUIView(context: Context) -> ViewportView {
        ViewportView(browser: browser)
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.fullWidth = fullWidth
        view.showRegions = showRegions
        view.reservesBrowserControls = reservesBrowserControls
        view.setNeedsLayout()
    }
}

final class ViewportView: UIView {
    let webView: WKWebView
    private weak var browser: BrowserModel?
    private var lastGeometry = ""
    var fullWidth = true
    var showRegions = false
    var reservesBrowserControls = true
    private let regionsLayer = CAShapeLayer()
    private var chromeObserver: AnyCancellable?
    private var collapse = 0.0
    private var expandedHeight: CGFloat = 52
    private var bottomControlLift: CGFloat = 0

    init(browser: BrowserModel) {
        self.browser = browser
        self.webView = browser.webView
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        addSubview(webView)
        regionsLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.2).cgColor
        regionsLayer.strokeColor = UIColor.systemOrange.cgColor
        regionsLayer.lineWidth = 2
        layer.addSublayer(regionsLayer)
        chromeObserver = browser.chrome.$progress.combineLatest(browser.chrome.$expandedHeight).sink { [weak self] progress, height in
            self?.collapse = progress
            if self?.expandedHeight != height { self?.expandedHeight = height; self?.setNeedsLayout() }
            self?.updateObscuredArea()
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(webView:)") }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = fullWidth ? bounds : safeAreaLayoutGuide.layoutFrame
        // Keep native controls clear of bottom camera/system occlusions in rotated poses.
        let occlusions = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        let lift = BrowserViewportState.controlLift(in: bounds, height: expandedHeight,
                                                    safeBottom: safeAreaInsets.bottom, regions: occlusions)
        if lift != bottomControlLift {
            bottomControlLift = lift
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.browser?.viewport.bottomControlLift != self.bottomControlLift {
                    self.browser?.viewport.bottomControlLift = self.bottomControlLift
                }
            }
        }
        // Reserve scrollable space beneath our floating controls, without narrowing the page.
        updateObscuredArea()
        // Keep the native indicator at the actual web-view edge, not the Duo's camera-safe inset.
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        regionsLayer.frame = bounds
        regionsLayer.isHidden = !showRegions
        let path = UIBezierPath()
        for region in reservedRegions(kind: .occlusion) + reservedRegions(kind: .division) {
            let area = region.frame
            path.append(UIBezierPath(rect: area))
        }
        regionsLayer.path = path.cgPath
        let regions: [[String: Double]] = fullWidth ? reservedRegions(kind: .occlusion).filter(\.isActive).map { region in
            let r = convert(region.frame, to: webView)
            return ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)]
        } : []
        let key = "\(webView.bounds.size)-\(regions)"
        if key != lastGeometry {
            lastGeometry = key
            browser?.updateGeometry(width: webView.bounds.width, height: webView.bounds.height, regions: regions)
        }
    }

    private func updateObscuredArea() {
        let expanded = expandedHeight + 8 + (fullWidth ? safeAreaInsets.bottom : 0)
        let bottom = expanded + (38 - expanded) * collapse + bottomControlLift
        // This public WebKit API moves fixed/sticky page controls above browser chrome.
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: reservesBrowserControls ? bottom : 0, right: 0)
        if webView.obscuredContentInsets != inset { webView.obscuredContentInsets = inset }
        webView.scrollView.contentInset.bottom = 0
        webView.scrollView.verticalScrollIndicatorInsets = inset
    }
}

private struct BrowserStartPage: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    let search: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Text(browser.isPrivate ? "Private Browsing" : "Start Page")
                            .font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, geometry.safeAreaInsets.trailing)
                    if browser.isPrivate {
                        Label("Private browsing", systemImage: "hand.raised.fill")
                            .font(.headline)
                        Text("Your private tabs and browsing history aren't saved.")
                            .foregroundStyle(.secondary)
                    } else {
                        section("Favorites", entries: Array(session.bookmarks.prefix(8)), empty: "Save a bookmark from Page options to see it here.", icon: "star")
                        section("Recently Visited", entries: Array(session.history.prefix(5)), empty: "Pages you visit will appear here.", icon: "clock")
                    }
                    Button(action: search) {
                        Label("Search or enter a website", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 120)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private func section(_ title: String, entries: [LibraryEntry], empty: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if entries.isEmpty {
                Label(empty, systemImage: icon).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 100), spacing: 16)], alignment: .leading, spacing: 18) {
                    ForEach(entries) { entry in
                        Button { browser.navigate(to: entry.address) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: icon).font(.title3).frame(width: 48, height: 48)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                Text(verbatim: entry.title.isEmpty ? (URL(string: entry.address)?.host ?? entry.address) : entry.title)
                                    .font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                            }.frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Opens this page")
                    }
                }
            }
        }
    }
}
