import SwiftUI
import UIKit
import WebKit

struct BrowserView: View {
    @StateObject private var browser = BrowserModel()
    @State private var input = ""
    @FocusState private var editingAddress: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            BrowserSurface(browser: browser)
                .ignoresSafeArea(.container)

            VStack(spacing: 8) {
                if let error = browser.errorMessage {
                    HStack {
                        Text(error).font(.callout)
                        Button("Dismiss") { browser.errorMessage = nil }
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                HStack(spacing: 0) {
                    Button { browser.webView.goBack() } label: {
                        Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                    }
                    .disabled(!browser.canGoBack)
                    .accessibilityLabel("Back")

                    TextField("Search or enter website", text: $input)
                        .font(.callout)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .focused($editingAddress)
                        .onSubmit {
                            editingAddress = false
                            browser.navigate(to: input)
                        }
                        .accessibilityLabel("Website address or search")

                    Button {
                        if browser.isLoading { browser.webView.stopLoading() }
                        else { browser.webView.reload() }
                    } label: {
                        Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(browser.isLoading ? "Stop loading" : "Reload")

                    Menu {
                        Toggle("Full width (experimental)", isOn: $browser.fullWidth)
                        Toggle("Show reserved regions", isOn: $browser.showRegions)
                        Button("Forward", systemImage: "chevron.forward") { browser.webView.goForward() }
                            .disabled(!browser.canGoForward)
                        Button("Open test page", systemImage: "ruler") { browser.loadFixture() }
                        Text("Camera avoidance is not implemented yet.")
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Browser options")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .overlay(alignment: .top) {
                    if browser.isLoading {
                        ProgressView(value: browser.progress)
                            .padding(.horizontal, 24)
                            .accessibilityLabel("Page loading")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: 620)
        }
        .onChange(of: browser.address) { _, newValue in
            if !editingAddress { input = newValue }
        }
    }
}

private struct BrowserSurface: UIViewRepresentable {
    @ObservedObject var browser: BrowserModel

    func makeUIView(context: Context) -> ViewportView {
        ViewportView(webView: browser.webView)
    }

    func updateUIView(_ view: ViewportView, context: Context) {
        view.fullWidth = browser.fullWidth
        view.showRegions = browser.showRegions
        view.setNeedsLayout()
    }
}

private final class ViewportView: UIView {
    let webView: WKWebView
    var fullWidth = false
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
        webView.scrollView.verticalScrollIndicatorInsets.bottom = webView.scrollView.contentInset.bottom
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
