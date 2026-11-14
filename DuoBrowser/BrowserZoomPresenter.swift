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
        controller.applyAppearance(session.appearance)
        controller.update(reduceMotion: reduceMotion || dynamicTypeSize.isAccessibilitySize)
    }
}

private struct BrowserScreen: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        ActiveBrowserView(session: session, browser: session.selected, viewport: session.selected.viewport)
            .id(session.selectedID)
            .sheet(isPresented: $session.showingSetup) { BrowserSetup(session: session, model: session.setup) }
            .sheet(isPresented: $session.showingLibrary) { BrowserLibrary(session: session) }
            .sheet(isPresented: $session.showingWorkspaces) { WorkspaceView(session: session) }
    }
}

final class BrowserZoomController: UIViewController {
    private let session: BrowserSession
    private let overview: UIHostingController<TabOverview>
    private let browser: TabSwipeController
    private var observation: AnyCancellable?
    private var appearanceObservation: AnyCancellable?
    private var reduceMotion = false
    private var appeared = false
    private var hasPresentedBrowser = false
    private var presentedTabID: UUID?

    init(session: BrowserSession) {
        self.session = session
        overview = UIHostingController(rootView: TabOverview(session: session))
        browser = TabSwipeController(content: UIHostingController(rootView: BrowserScreen(session: session)), session: session)
        super.init(nibName: nil, bundle: nil)
        overview.safeAreaRegions = .keyboard
        browser.modalPresentationStyle = .fullScreen
        browser.isModalInPresentation = true
        // The presenting SwiftUI hierarchy can be offscreen beneath the full-screen browser.
        // Observe presentation intent here so its update cycle cannot stall dismissal.
        appearanceObservation = session.$appearance.sink { [weak self] appearance in self?.applyAppearance(appearance) }
        // A repeated Tabs tap is also a reconciliation request after a cancelled UIKit transition.
        observation = session.$showingTabs.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
        browser.presentationDidChange = { [weak self] in
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

    func applyAppearance(_ appearance: BrowserAppearance) {
        let style: UIUserInterfaceStyle = appearance == .system ? .unspecified : appearance == .dark ? .dark : .light
        overrideUserInterfaceStyle = style
        overview.overrideUserInterfaceStyle = style
        browser.overrideUserInterfaceStyle = style
    }

    func update(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        browser.reduceMotion = reduceMotion
        // Let SwiftUI update the selected card and its collection snapshot first.
        Task { @MainActor [weak self] in self?.reconcile() }
    }

    private func reconcile() {
        guard appeared, view.window != nil || browser.viewIfLoaded?.window != nil else { return }
        // UIKit can cancel a transition without reaching the original completion path.
        // Actual presentation state is authoritative; a local latch must not disable Tabs.
        if let active = activeUIKitTransition() {
            active.transitionCoordinator?.animate(alongsideTransition: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcile() }
            }
            return
        }
        if session.showingTabs {
            guard browser.presentingViewController != nil else { return }
            configureTransition()
            browser.dismiss(animated: true) { [weak self] in
                self?.reconcile()
            }
        } else {
            guard presentedViewController == nil, browser.presentingViewController == nil else { return }
            configureTransition()
            let animate = hasPresentedBrowser
            hasPresentedBrowser = true
            presentedTabID = session.selectedID
            present(browser, animated: animate) { [weak self] in
                self?.reconcile()
            }
        }
    }

    private func activeUIKitTransition() -> UIViewController? {
        var current: UIViewController? = self
        while let controller = current {
            if controller.isBeingPresented || controller.isBeingDismissed { return controller }
            current = controller.presentedViewController
        }
        return nil
    }

    private func configureTransition() {
        if reduceMotion || UIAccessibility.isReduceMotionEnabled || UIAccessibility.isVoiceOverRunning || session.tabOverviewStyle == .list
            || session.showingTabs && presentedTabID != session.selectedID {
            // A live New Tab/tab swipe changes the document inside the already-presented
            // controller. Its new card did not supply that presentation's matched zoom.
            browser.preferredTransition = .crossDissolve
        } else {
            overview.view.layoutIfNeeded()
            guard let source = findStack(in: overview)?.zoomSource(for: session.selectedID, centered: session.showingTabs),
                  source.bounds.width > 0, source.bounds.height > 0,
                  source.isDescendant(of: overview.view) else {
                // New Tab can replace the live document while the overview is offscreen.
                // Its card may not exist yet; never start a native zoom without a source.
                browser.preferredTransition = .crossDissolve
                return
            }
            let options = UIViewController.Transition.ZoomOptions()
            // Browser pinch and edge gestures belong to WebKit, not modal dismissal.
            options.interactiveDismissShouldBegin = { _ in false }
            browser.preferredTransition = .zoom(options: options) { [weak source, weak overview] _ in
                guard let overview else { return source }
                if let source, source.isDescendant(of: overview.view) { return source }
                return overview.view
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
