import SwiftUI
import UIKit
import Combine

enum TabOverviewStyle: String, CaseIterable {
    case grid, list
    var title: String { self == .grid ? "Grid" : "List" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum TabSwipeMotion {
    static func shouldCommit(translation: CGFloat, predicted: CGFloat, width: CGFloat) -> Bool {
        guard translation.isFinite, predicted.isFinite, width.isFinite, width > 0,
              abs(translation) >= 28, translation * predicted >= 0 else { return false }
        return abs(translation) > width * 0.22 || abs(predicted) > width * 0.46
    }
}

/// Gesture events contain only bounded movement. A controller owns all temporary presentation.
@MainActor
final class TabSwipeState {
    enum Event {
        case changed(CGFloat)
        case ended(CGFloat, CGFloat)
        case cancelled
    }
    var receive: ((Event) -> Void)?
}

struct TabSwipeGestureModifier: ViewModifier {
    let session: BrowserSession
    let enabled: Bool
    @GestureState private var touching = false
    @State private var dragging = false

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    guard enabled else { return }
                    guard dragging || abs(value.translation.width) > abs(value.translation.height) * 1.6 else { return }
                    dragging = true
                    session.tabSwipe.receive?(.changed(value.translation.width))
                }
                .onEnded { value in
                    guard dragging else { return }
                    dragging = false
                    if enabled { session.tabSwipe.receive?(.ended(value.translation.width, value.predictedEndTranslation.width)) }
                    else { session.tabSwipe.receive?(.cancelled) }
                }
        )
        .onChange(of: touching) { _, active in
            guard !active else { return }
            // A failed or system-cancelled recognizer has no onEnded callback.
            Task { @MainActor in
                guard !touching, dragging else { return }
                dragging = false
                session.tabSwipe.receive?(.cancelled)
            }
        }
        .onChange(of: enabled) { _, value in
            if !value { dragging = false; session.tabSwipe.receive?(.cancelled) }
        }
        .onDisappear { dragging = false; session.tabSwipe.receive?(.cancelled) }
    }
}

/// The live page remains attached to one host throughout a drag. Neighbor previews are ephemeral
/// in-memory snapshots; selection reparents an existing tab only after a validated commitment.
@MainActor
final class TabSwipeController: UIViewController {
    private let content: UIViewController
    private let session: BrowserSession
    private let preview = UIView()
    private let image = UIImageView()
    private let siteTitleLabel = UILabel()
    private let symbol = UIImageView(image: UIImage(systemName: "globe"))
    private var returningPreview: UIView?
    private var returningDirection = 0
    private var subscriptions: [AnyCancellable] = []
    private var sourceID: UUID?
    private var targetID: UUID?
    private var direction = 0
    private var initialBounds = CGRect.zero
    private var animator: UIViewPropertyAnimator?
    private var finishing = false
    private var dragOffset: CGFloat = 0
    private var opacityOffset: CGFloat = 0
    private var animationStartX: CGFloat = 0
    private var animationStartAlpha: CGFloat = 1
    private var caughtPresentation = false
    var reduceMotion = false
    var hasActivePresentation: Bool { sourceID != nil }

    init(content: UIViewController, session: BrowserSession) {
        self.content = content
        self.session = session
        super.init(nibName: nil, bundle: nil)
        session.tabSwipe.receive = { [weak self] event in self?.receive(event) }
        session.$selectedID.dropFirst().sink { [weak self] _ in self?.cancelImmediately() }.store(in: &subscriptions)
        session.$showingTabs.dropFirst().sink { [weak self] _ in self?.cancelImmediately() }.store(in: &subscriptions)
        session.$workspaceID.dropFirst().sink { [weak self] _ in self?.cancelImmediately() }.store(in: &subscriptions)
        session.$privateMode.dropFirst().sink { [weak self] _ in self?.cancelImmediately() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.cancelImmediately() }.store(in: &subscriptions)
    }

    required init?(coder: NSCoder) { fatalError("Use init(content:session:)") }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForStatusBarStyle: UIViewController? { content }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preview.backgroundColor = .systemBackground
        preview.isUserInteractionEnabled = false
        preview.isAccessibilityElement = false
        preview.accessibilityElementsHidden = true
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        preview.addSubview(image)
        symbol.tintColor = .tertiaryLabel
        symbol.contentMode = .scaleAspectFit
        preview.addSubview(symbol)
        siteTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        siteTitleLabel.adjustsFontForContentSizeCategory = true
        siteTitleLabel.textColor = .label
        siteTitleLabel.textAlignment = .center
        siteTitleLabel.numberOfLines = 2
        siteTitleLabel.backgroundColor = .secondarySystemBackground
        siteTitleLabel.layer.cornerRadius = 18
        siteTitleLabel.layer.masksToBounds = true
        preview.addSubview(siteTitleLabel)
        preview.isHidden = true
        view.addSubview(preview)
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
        view.clipsToBounds = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if sourceID != nil, view.bounds != initialBounds { cancelImmediately() }
        preview.frame = view.bounds
        image.frame = preview.bounds
        symbol.frame = CGRect(x: preview.bounds.midX - 28, y: preview.bounds.midY - 28, width: 56, height: 56)
        let safe = view.safeAreaInsets
        let width = max(0, min(340, view.bounds.width - safe.left - safe.right - 40))
        siteTitleLabel.frame = CGRect(x: (view.bounds.width - width) / 2, y: view.bounds.height - max(20, safe.bottom) - 68,
                             width: width, height: 52)
    }

    override func viewWillDisappear(_ animated: Bool) {
        cancelImmediately()
        super.viewWillDisappear(animated)
    }

    private var sourceIsCurrent: Bool {
        sourceID == session.selectedID && !session.showingTabs
    }

    private var valid: Bool {
        guard let targetID else { return false }
        return sourceIsCurrent && session.adjacentTabID(direction) == targetID
    }

    private func receive(_ event: TabSwipeState.Event) {
        guard isViewLoaded else { return }
        switch event {
        case .changed(let distance):
            guard distance.isFinite, view.window != nil,
                  presentedViewController == nil, content.presentedViewController == nil else { return }
            if finishing {
                guard sourceIsCurrent else { cancelImmediately(); return }
                guard interruptSettling(at: distance) else { return }
            }
            if sourceID == nil {
                guard abs(distance) >= 16, let neighbor = session.adjacentTabID(distance < 0 ? 1 : -1) else { return }
                direction = distance < 0 ? 1 : -1
                sourceID = session.selectedID
                targetID = neighbor
                dragOffset = 0
                opacityOffset = 0
                caughtPresentation = false
                initialBounds = view.bounds
                updatePreview(for: neighbor)
                view.layoutIfNeeded()
            }
            guard valid else { cancelImmediately(); return }
            let bounded = max(-view.bounds.width, min(view.bounds.width, distance + dragOffset))
            // A caught page can still be on the other side of zero. Its prior position
            // remains presentation context, never a substitute for the new gesture's intent.
            let displacement = caughtPresentation || bounded * CGFloat(direction) < 0 ? bounded : bounded * 0.12
            if reduceMotion || UIAccessibility.isReduceMotionEnabled {
                content.view.alpha = max(0, min(1, 1 + opacityOffset - min(0.25, abs(displacement) / max(1, view.bounds.width) * 0.25)))
            } else {
                content.view.transform = CGAffineTransform(translationX: displacement, y: 0)
                preview.transform = CGAffineTransform(translationX: displacement + CGFloat(direction) * view.bounds.width, y: 0)
                returningPreview?.transform = CGAffineTransform(translationX: displacement + CGFloat(returningDirection) * view.bounds.width, y: 0)
            }
        case .ended(let distance, let predicted):
            guard sourceID != nil else { return }
            let commit = valid && distance * CGFloat(direction) < 0 && TabSwipeMotion.shouldCommit(
                translation: distance, predicted: predicted, width: view.bounds.width)
            finish(commit: commit)
        case .cancelled:
            if sourceID != nil, !finishing { finish(commit: false) }
        }
    }

    private func updatePreview(for id: UUID) {
        guard let target = session.tabs.first(where: { $0.id == id }) else { return }
        image.image = target.snapshot
        symbol.isHidden = target.snapshot != nil
        siteTitleLabel.text = target.isPrivate ? "Private · " + target.siteName : target.siteName
        preview.isHidden = false
    }

    /// Fresh intent chooses a fresh neighbor. Only the visual origin carries over.
    private func interruptSettling(at distance: CGFloat) -> Bool {
        guard distance != 0 else { return false }
        let presentation = content.view.layer.presentation()
        let currentX = presentation?.affineTransform().tx ?? animationStartX
        let currentAlpha = presentation.map { CGFloat($0.opacity) } ?? animationStartAlpha
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
        finishing = false
        caughtPresentation = true
        let nextDirection = distance < 0 ? 1 : -1
        let reduced = reduceMotion || UIAccessibility.isReduceMotionEnabled
        if direction != nextDirection {
            returningPreview?.removeFromSuperview()
            returningPreview = nil
            if !reduced, !preview.isHidden, let frozen = preview.snapshotView(afterScreenUpdates: false) {
                frozen.frame = view.bounds
                frozen.isUserInteractionEnabled = false
                frozen.isAccessibilityElement = false
                frozen.accessibilityElementsHidden = true
                returningDirection = direction
                frozen.transform = CGAffineTransform(translationX: currentX + CGFloat(returningDirection) * view.bounds.width, y: 0)
                view.insertSubview(frozen, belowSubview: content.view)
                returningPreview = frozen
            }
            direction = nextDirection
        }
        targetID = session.adjacentTabID(direction)
        if let targetID { updatePreview(for: targetID) }
        else { preview.isHidden = true }
        if reduced {
            dragOffset = -distance
            opacityOffset = currentAlpha - 1
            content.view.alpha = currentAlpha
        } else {
            dragOffset = currentX - distance
            content.view.transform = CGAffineTransform(translationX: currentX, y: 0)
            preview.transform = CGAffineTransform(translationX: currentX + CGFloat(direction) * view.bounds.width, y: 0)
            returningPreview?.transform = CGAffineTransform(translationX: currentX + CGFloat(returningDirection) * view.bounds.width, y: 0)
        }
        guard targetID != nil else { finish(commit: false); return false }
        return true
    }

    private func finish(commit: Bool) {
        guard !finishing else { return }
        finishing = true
        let target = targetID
        let reduced = reduceMotion || UIAccessibility.isReduceMotionEnabled
        let finalX = commit ? -CGFloat(direction) * view.bounds.width : 0
        animationStartX = content.view.layer.presentation()?.affineTransform().tx ?? content.view.transform.tx
        animationStartAlpha = content.view.layer.presentation().map { CGFloat($0.opacity) } ?? content.view.alpha
        CATransaction.flush()
        animator = UIViewPropertyAnimator(duration: reduced ? 0.12 : 0.24, curve: .easeOut) {
            if reduced { self.content.view.alpha = commit ? 0 : 1 }
            else {
                self.content.view.transform = CGAffineTransform(translationX: finalX, y: 0)
                self.preview.transform = CGAffineTransform(translationX: finalX + CGFloat(self.direction) * self.view.bounds.width, y: 0)
                self.returningPreview?.transform = CGAffineTransform(translationX: finalX + CGFloat(self.returningDirection) * self.view.bounds.width, y: 0)
            }
        }
        animator?.addCompletion { [weak self] position in
            guard let self, position == .end else { return }
            let shouldSelect = commit && self.valid
            self.cancelImmediately()
            if shouldSelect, let target { self.session.select(target) }
        }
        animator?.startAnimation()
    }

    func cancelImmediately() {
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
        sourceID = nil
        targetID = nil
        direction = 0
        finishing = false
        dragOffset = 0
        opacityOffset = 0
        caughtPresentation = false
        guard isViewLoaded else { return }
        content.view.transform = .identity
        content.view.alpha = 1
        preview.transform = .identity
        preview.isHidden = true
        image.image = nil
        siteTitleLabel.text = nil
        returningPreview?.removeFromSuperview()
        returningPreview = nil
        returningDirection = 0
    }
}
