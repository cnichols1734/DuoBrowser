import SwiftUI
import UIKit
import WebKit

struct BrowserView: View {
    @StateObject private var session = BrowserSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ActiveBrowserView(session: session, browser: session.selected)
            .id(session.selectedID)
            .fullScreenCover(isPresented: $session.showingTabs) {
                TabOverview(session: session)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { session.save() }
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
                BrowserSurface(browser: browser, fullWidth: session.fullWidth, showRegions: session.showRegions)
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
        .statusBarHidden(session.fullWidth)
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
        ViewportView(webView: browser.webView)
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.fullWidth = fullWidth
        view.showRegions = showRegions
        view.setNeedsLayout()
    }
}

private final class ViewportView: UIView {
    let webView: WKWebView
    var fullWidth = true
    var showRegions = false
    private let regionsLayer = CAShapeLayer()

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        addSubview(webView)
        regionsLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.2).cgColor
        regionsLayer.strokeColor = UIColor.systemOrange.cgColor
        regionsLayer.lineWidth = 2
        layer.addSublayer(regionsLayer)
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
        webView.scrollView.contentInset.bottom = 76 + (fullWidth ? safeAreaInsets.bottom : 0)
        // Keep the native indicator at the actual web-view edge, not the Duo's camera-safe inset.
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: 0, left: 0, bottom: webView.scrollView.contentInset.bottom, right: 0
        )
        regionsLayer.frame = bounds
        regionsLayer.isHidden = !showRegions
        let path = UIBezierPath()
        for region in reservedRegions(kind: .occlusion) + reservedRegions(kind: .division) {
            let area = CGRect(x: region.frame.minX - region.margins.left,
                              y: region.frame.minY - region.margins.top,
                              width: region.frame.width + region.margins.left + region.margins.right,
                              height: region.frame.height + region.margins.top + region.margins.bottom)
            path.append(UIBezierPath(rect: area))
        }
        regionsLayer.path = path.cgPath
    }
}
