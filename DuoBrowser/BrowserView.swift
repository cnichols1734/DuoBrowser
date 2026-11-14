import SwiftUI
import UIKit
import WebKit
import Combine
import BrowserKit

struct BrowserView: View {
    @StateObject private var session = BrowserSession()
    @State private var checkedInitialSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        BrowserZoomPresenter(session: session)
            .ignoresSafeArea(.container)
            .onOpenURL {
                session.setup.cancel()
                session.showingSetup = false
                session.openExternalURL($0)
            }
            .onAppear {
                guard !checkedInitialSetup else { return }
                checkedInitialSetup = true
                if !session.setup.completed { session.showingSetup = true }
            }
            .onContinueUserActivity(BEBrowserDataImportManager.userActivityType) { activity in
                if session.setup.receive(activity, isPrivate: session.privateMode) {
                    session.showingTabs = false
                    session.showingLibrary = false
                    session.showingWorkspaces = false
                    session.showingSetup = true
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.background() }
            }
    }
}

struct ActiveBrowserView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var viewport: BrowserViewportState
    @State private var input = ""
    @State private var keyboardVisible = false
    @State private var showingSearch = false
    @State private var noticeHeight: CGFloat = 0
    @State private var recoveryHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize


    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                BrowserSurface(browser: browser, fullWidth: browser.fullWidthLayout, showRegions: session.showRegions,
                               additionalBottomObstruction: showingSearch ? 0 :
                                   (session.privateMode || noticeHeight == 0 ? 0 : noticeHeight + 8) + (recoveryHeight > 0 ? recoveryHeight + 8 : 0))
                    .ignoresSafeArea(.container)
                    .blur(radius: showingSearch ? 5 : 0)
                    .accessibilityHidden(showingSearch || browser.showingStartPage || browser.failureCoversPage)
                    .allowsHitTesting(!showingSearch && !browser.showingStartPage && !browser.failureCoversPage)
                if browser.failureCoversPage {
                    BrowserRecoveryView(session: session, browser: browser, fillsPage: true, editAddress: openAddress)
                        .padding(.horizontal, max(16, max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing)))
                        .padding(.top, geometry.safeAreaInsets.top)
                        .padding(.bottom, browser.chrome.expandedHeight + viewport.bottomControlLift + geometry.safeAreaInsets.bottom + 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                        .accessibilityHidden(showingSearch).allowsHitTesting(!showingSearch)
                } else if browser.showingStartPage {
                    BrowserStartPage(session: session, browser: browser, chrome: browser.chrome, viewport: viewport,
                                     onSearch: { input = ""; showingSearch = true })
                        .blur(radius: showingSearch ? 5 : 0)
                        .accessibilityHidden(showingSearch)
                        .allowsHitTesting(!showingSearch)
                }
                VStack(spacing: 8) {
                    ClosedTabNotice(session: session) { noticeHeight = $0 }
                    if browser.errorMessage != nil, !browser.failureCoversPage {
                        BrowserRecoveryView(session: session, browser: browser, fillsPage: false, editAddress: openAddress,
                                            maximumHeight: max(80, geometry.size.height - browser.chrome.expandedHeight - viewport.bottomControlLift - geometry.safeAreaInsets.bottom - noticeHeight - 40))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { recoveryHeight = $0 }
                            .onDisappear { recoveryHeight = 0 }
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
        .onAppear { input = BrowserAddressIdentity(browser: browser).editingAddress }
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

    private func openAddress() {
        input = BrowserAddressIdentity(browser: browser).editingAddress
        showingSearch = true
    }
}

struct BrowserSurface: UIViewRepresentable {
    let browser: BrowserModel
    let fullWidth: Bool
    let showRegions: Bool
    var reservesBrowserControls = true
    var additionalBottomObstruction: CGFloat = 0

    func makeUIView(context: Context) -> ViewportView {
        ViewportView(browser: browser)
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.fullWidth = fullWidth
        view.showRegions = showRegions
        view.reservesBrowserControls = reservesBrowserControls
        view.additionalBottomObstruction = additionalBottomObstruction
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
    var additionalBottomObstruction: CGFloat = 0
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
        let lift = BrowserViewportState.controlLift(in: bounds, height: expandedHeight + additionalBottomObstruction,
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
        let bottom = expanded + (38 - expanded) * collapse + bottomControlLift + additionalBottomObstruction
        // This public WebKit API moves fixed/sticky page controls above browser chrome.
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: reservesBrowserControls ? bottom : 0, right: 0)
        if webView.obscuredContentInsets != inset { webView.obscuredContentInsets = inset }
        webView.scrollView.contentInset.bottom = 0
        webView.scrollView.verticalScrollIndicatorInsets = inset
    }
}
