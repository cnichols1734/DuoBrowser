import SwiftUI
import UIKit
import Combine

/// The overview is the source; the live browser zooms above it in both directions.
/// UIKit owns the transition, with no page bitmap copies or replacement WKWebViews.
struct BrowserZoomPresenter: UIViewControllerRepresentable {
    @ObservedObject var session: BrowserSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeUIViewController(context: Context) -> BrowserZoomController {
        BrowserZoomController(session: session)
    }

    func updateUIViewController(_ controller: BrowserZoomController, context: Context) {
        controller.update(reduceMotion: reduceMotion || dynamicTypeSize.isAccessibilitySize)
    }
}

private struct BrowserScreen: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        ActiveBrowserView(session: session, browser: session.selected, viewport: session.selected.viewport)
            .id(session.selectedID)
            .sheet(isPresented: $session.showingLibrary) { BrowserLibrary(session: session) }
            .sheet(isPresented: $session.showingWorkspaces) { WorkspaceView(session: session) }
    }
}

final class BrowserZoomController: UIViewController {
    private let session: BrowserSession
    private let overview: UIHostingController<TabOverview>
    private let browser: UIHostingController<BrowserScreen>
    private var observation: AnyCancellable?
    private var reduceMotion = false
    private var transitioning = false
    private var appeared = false
    private var hasPresentedBrowser = false

    init(session: BrowserSession) {
        self.session = session
        overview = UIHostingController(rootView: TabOverview(session: session))
        browser = UIHostingController(rootView: BrowserScreen(session: session))
        super.init(nibName: nil, bundle: nil)
        browser.modalPresentationStyle = .fullScreen
        browser.isModalInPresentation = true
        // The presenting SwiftUI hierarchy can be offscreen beneath the full-screen browser.
        // Observe presentation intent here so its update cycle cannot stall dismissal.
        observation = session.$showingTabs.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(overview)
        overview.view.frame = view.bounds
        overview.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overview.view)
        overview.didMove(toParent: self)
    }

    override var childForStatusBarHidden: UIViewController? { overview }
    override var childForStatusBarStyle: UIViewController? { overview }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        reconcile()
    }

    func update(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        // Let SwiftUI update the selected card and its collection snapshot first.
        Task { @MainActor [weak self] in self?.reconcile() }
    }

    private func reconcile() {
        guard appeared, !transitioning, view.window != nil || browser.viewIfLoaded?.window != nil else { return }
        if session.showingTabs {
            guard browser.presentingViewController != nil else { return }
            configureTransition()
            transitioning = true
            browser.dismiss(animated: true) { [weak self] in
                self?.transitioning = false
                self?.reconcile()
            }
        } else {
            guard presentedViewController == nil, browser.presentingViewController == nil else { return }
            configureTransition()
            transitioning = true
            let animate = hasPresentedBrowser
            hasPresentedBrowser = true
            present(browser, animated: animate) { [weak self] in
                self?.transitioning = false
                self?.reconcile()
            }
        }
    }

    private func configureTransition() {
        if reduceMotion || UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning {
            browser.preferredTransition = .crossDissolve
        } else {
            let options = UIViewController.Transition.ZoomOptions()
            // Browser pinch and edge gestures belong to WebKit, not modal dismissal.
            options.interactiveDismissShouldBegin = { _ in false }
            browser.preferredTransition = .zoom(options: options) { [weak self] _ in
                guard let self else { return nil }
                self.overview.view.layoutIfNeeded()
                return self.findStack(in: self.overview)?.zoomSource(for: self.session.selectedID, centered: self.session.showingTabs)
            }
        }
    }

    private func findStack(in controller: UIViewController) -> TabStackController? {
        if let stack = controller as? TabStackController { return stack }
        for child in controller.children {
            if let stack = findStack(in: child) { return stack }
        }
        return nil
    }
}
