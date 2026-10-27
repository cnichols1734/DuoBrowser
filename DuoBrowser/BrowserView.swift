import SwiftUI
import UIKit
import WebKit
import Combine

struct BrowserView: View {
    @StateObject private var session = BrowserSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ActiveBrowserView(session: session, browser: session.selected)
            .id(session.selectedID)
            .fullScreenCover(isPresented: $session.showingTabs) {
                TabOverview(session: session)
            }
            .sheet(isPresented: $session.showingLibrary) { BrowserLibrary(session: session) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.background() }
            }
    }
}

private struct ActiveBrowserView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @State private var input = ""
    @State private var keyboardVisible = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                BrowserSurface(browser: browser, fullWidth: browser.fullWidthLayout, showRegions: session.showRegions)
                    .ignoresSafeArea(.container)
                VStack(spacing: 8) {
                    if let error = browser.errorMessage {
                        HStack {
                            Text(error).font(.callout)
                            Button("Dismiss") { browser.errorMessage = nil }
                        }
                        .padding(12)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 12)
                    }
                    BrowserToolbar(session: session, browser: browser, chrome: browser.chrome,
                                   input: $input, keyboardVisible: keyboardVisible,
                                   bottomSafeArea: geometry.safeAreaInsets.bottom,
                                   accessibilityExpanded: voiceOverEnabled || dynamicTypeSize.isAccessibilitySize)
                }
                .padding(.bottom, 8)
            }
            // Only the bottom controls reclaim the horizontal camera-safe rail. Keep keyboard/bottom safety.
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .statusBarHidden(browser.fullWidthLayout)
        .onAppear { input = browser.address }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
            browser.revealControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }
}

private struct BrowserSurface: UIViewRepresentable {
    let browser: BrowserModel
    let fullWidth: Bool
    let showRegions: Bool

    func makeUIView(context: Context) -> ViewportView {
        ViewportView(browser: browser)
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.fullWidth = fullWidth
        view.showRegions = showRegions
        view.setNeedsLayout()
    }
}

private final class ViewportView: UIView {
    let webView: WKWebView
    private weak var browser: BrowserModel?
    private var lastGeometry = ""
    var fullWidth = true
    var showRegions = false
    private let regionsLayer = CAShapeLayer()
    private var chromeObserver: AnyCancellable?
    private var collapse = 0.0

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
        chromeObserver = browser.chrome.$progress.sink { [weak self] progress in
            self?.collapse = progress
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
        let expanded = 60 + (fullWidth ? safeAreaInsets.bottom : 0)
        let bottom = expanded + (38 - expanded) * collapse
        // This public WebKit API moves fixed/sticky page controls above browser chrome.
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
        if webView.obscuredContentInsets != inset { webView.obscuredContentInsets = inset }
        webView.scrollView.contentInset.bottom = 0
        webView.scrollView.verticalScrollIndicatorInsets = inset
    }
}
