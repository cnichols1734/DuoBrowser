import SwiftUI
import UIKit
import Combine

/// A native vertical grid owns scrolling, card dismissal and stable zoom sources.
struct TabStack<Content: View>: UIViewControllerRepresentable {
    let tabs: [BrowserModel]
    let selectedID: UUID
    let reduceMotion: Bool
    let close: (UUID) -> Void
    @ViewBuilder var content: (BrowserModel, @escaping () -> Void) -> Content

    func makeUIViewController(context: Context) -> TabStackController { TabStackController() }

    static func dismantleUIViewController(_ controller: TabStackController, coordinator: ()) {
        controller.finishPendingDismissals()
    }

    func updateUIViewController(_ controller: TabStackController, context: Context) {
        controller.update(tabs: tabs, selectedID: selectedID, reduceMotion: reduceMotion, close: close) { tab, dismiss in
            AnyView(content(tab, dismiss))
        }
    }
}

/// A leftward drag commits only after meaningful travel or a deliberate flick.
enum TabStackMotion {
    nonisolated static func shouldDismiss(translation: CGFloat, velocity: CGFloat, width: CGFloat) -> Bool {
        guard translation.isFinite, velocity.isFinite, width > 0,
              translation < -24, velocity < 120 else { return false }
        return -(translation + velocity * 0.099) > width * 0.32
    }
}

final class TabStackLayout: UICollectionViewFlowLayout {
    var reduceMotion = false
    var cardWidth: CGFloat { itemSize.width }

    override func prepare() {
        guard let collectionView else { return }
        let width = collectionView.bounds.width
        let columns = max(1, Int((width - 16) / 200))
        let count = width >= 360 ? max(2, columns) : columns
        let available = max(1, width - 32 - CGFloat(count - 1) * 16)
        itemSize = CGSize(width: floor(available / CGFloat(count)), height: floor(available / CGFloat(count)) / 0.72 + 36)
        minimumInteritemSpacing = 16
        minimumLineSpacing = 24
        sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }
}

final class TabCardGeometry: ObservableObject {
    @Published var closeOrigin: CGPoint? = .zero

    static func closeOrigin(in bounds: CGRect, regions: [CGRect], rightToLeft: Bool) -> CGPoint? {
        let size: CGFloat = 48
        guard bounds.width >= size, bounds.height >= size else { return nil }
        let left = bounds.minX, right = bounds.maxX - size
        let columns = rightToLeft ? [left, right] : [right, left]
        let rows = ([bounds.minY] + regions.map { $0.maxY + 4 } + [bounds.maxY - size]).sorted()
        for y in rows where y >= bounds.minY && y + size <= bounds.maxY {
            for x in columns {
                let target = CGRect(x: x, y: y, width: size, height: size)
                if !regions.contains(where: { $0.intersects(target) }) { return target.origin }
            }
        }
        return nil // A fully covered card retains its context-menu and swipe close actions.
    }
}

final class TabStackCell: UICollectionViewCell {
    var representedID: UUID?
    let geometry = TabCardGeometry()
    private var titleObservation: AnyCancellable?
    // UIKit owns contentView's transform. Keep interactive motion on our own container.
    let motionView = UIView()
    let previewView = UIView()
    private let titleLabel = UILabel()
    private var host: UIHostingController<AnyView>?
    private weak var hostingParent: UIViewController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        motionView.frame = contentView.bounds
        motionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(motionView)
        previewView.clipsToBounds = true
        previewView.layer.cornerRadius = 18
        previewView.layer.cornerCurve = .continuous
        motionView.addSubview(previewView)
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isAccessibilityElement = false
        motionView.addSubview(titleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width / 0.72)
        titleLabel.frame = CGRect(x: 4, y: previewView.frame.maxY + 8, width: max(0, bounds.width - 8), height: 24)
    }

    func observeTitle(of tab: BrowserModel) {
        titleObservation = tab.$title.combineLatest(tab.$isPinned).sink { [weak self] title, pinned in
            self?.titleLabel.text = (pinned ? "📌 " : "") + title
        }
    }

    func updateOcclusions() {
        guard let window else { return }
        let regions = window.reservedRegions(kind: .occlusion).filter(\.isActive).map {
            previewView.convert($0.frame, from: window)
        }
        let origin = TabCardGeometry.closeOrigin(in: previewView.bounds, regions: regions,
                                                rightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        if origin != geometry.closeOrigin { geometry.closeOrigin = origin }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleObservation = nil
        host?.rootView = AnyView(EmptyView())
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let host else { return }
        if window == nil, host.parent != nil {
            host.willMove(toParent: nil)
            host.removeFromParent()
        } else if window != nil, host.parent == nil, let hostingParent {
            hostingParent.addChild(host)
            host.didMove(toParent: hostingParent)
        }
    }

    func configure(_ content: AnyView, parent: UIViewController) {
        hostingParent = parent
        if let host { host.rootView = content }
        else {
            let controller = UIHostingController(rootView: content)
            controller.safeAreaRegions = []
            controller.view.backgroundColor = .clear
            parent.addChild(controller)
            controller.view.frame = previewView.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            previewView.addSubview(controller.view)
            controller.didMove(toParent: parent)
            host = controller
        }
    }

}

final class TabStackController: UIViewController, UIGestureRecognizerDelegate, UICollectionViewDelegate {
    let stackLayout = TabStackLayout()
    private(set) lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: stackLayout)
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private var tabs: [BrowserModel] = []
    private var selectedID: UUID?
    private var makeCard: ((BrowserModel, @escaping () -> Void) -> AnyView)?
    private var close: ((UUID) -> Void)?
    private var initialFocus: UUID?
    private var previousSize: CGSize = .zero
    private var swipe: UIPanGestureRecognizer!
    private var draggedID: UUID?
    private var pendingDragID: UUID?
    private var recognitionTranslation: CGFloat = 0
    private weak var draggedCell: TabStackCell?
    private var dragStart: CGFloat = 0
    private var animators: [UUID: UIViewPropertyAnimator] = [:]
    private var closingIDs: Set<UUID> = []

    override func loadView() {
        view = collectionView
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.alwaysBounceVertical = true
        collectionView.decelerationRate = .normal
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.clipsToBounds = true
        collectionView.register(TabStackCell.self, forCellWithReuseIdentifier: "tab")
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) { [weak self] collection, path, id in
            guard let self, let tab = self.tabs.first(where: { $0.id == id }) else { return nil }
            guard let cell = collection.dequeueReusableCell(withReuseIdentifier: "tab", for: path) as? TabStackCell else { return nil }
            if cell.representedID != id {
                if let previous = cell.representedID {
                    self.animators.removeValue(forKey: previous)?.stopAnimation(true)
                    // A fast vertical scroll may recycle a departing card. Complete its committed close
                    // on the next turn, outside UIKit's cell-provider callback, without moving the new card.
                    if self.closingIDs.contains(previous) {
                        Task { @MainActor [weak self] in self?.finishDismissal(previous) }
                    }
                }
                cell.motionView.layer.removeAnimation(forKey: "DuoBrowser.dismiss")
                cell.motionView.transform = .identity
                cell.motionView.alpha = 1
                cell.representedID = id
            }
            cell.configure(AnyView((self.makeCard?(tab, { [weak self] in self?.dismiss(id, velocity: 0) }) ?? AnyView(EmptyView()))
                .environmentObject(cell.geometry)), parent: self)
            cell.observeTitle(of: tab)
            return cell
        }
        swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.delegate = self
        swipe.maximumNumberOfTouches = 1
        collectionView.addGestureRecognizer(swipe)
        collectionView.panGestureRecognizer.require(toFail: swipe)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateOcclusions()
        guard collectionView.bounds.width > 0, collectionView.bounds.size != previousSize else { return }
        let focus = initialFocus ?? collectionView.indexPathsForVisibleItems.sorted().first.flatMap { dataSource.itemIdentifier(for: $0) }
        previousSize = collectionView.bounds.size
        stackLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        initialFocus = nil
        if let focus, let path = dataSource.indexPath(for: focus) {
            collectionView.scrollToItem(at: path, at: .top, animated: false)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateOcclusions() }

    private func updateOcclusions() {
        for case let cell as TabStackCell in collectionView.visibleCells { cell.updateOcclusions() }
    }

    func update(tabs: [BrowserModel], selectedID: UUID, reduceMotion: Bool, close: @escaping (UUID) -> Void,
                makeCard: @escaping (BrowserModel, @escaping () -> Void) -> AnyView) {
        loadViewIfNeeded()
        self.close = close
        self.makeCard = makeCard
        if stackLayout.reduceMotion != reduceMotion {
            stackLayout.reduceMotion = reduceMotion
            stackLayout.invalidateLayout()
        }
        let oldIDs = self.tabs.map(\.id), ids = tabs.map(\.id)
        let selectionChanged = self.selectedID != selectedID
        self.selectedID = selectedID
        guard oldIDs != ids || selectionChanged else { return }
        cancelDrag()
        for removed in Set(oldIDs).subtracting(ids) {
            animators.removeValue(forKey: removed)?.stopAnimation(true)
            finishDismissal(removed)
        }
        self.tabs = tabs
        if previousSize == .zero { initialFocus = selectedID }
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        if selectionChanged { snapshot.reconfigureItems(ids.filter(oldIDs.contains)) }
        dataSource.apply(snapshot, animatingDifferences: !reduceMotion && !oldIDs.isEmpty)
    }

    func zoomSource(for id: UUID, centered: Bool) -> UIView? {
        guard let path = dataSource.indexPath(for: id), !closingIDs.contains(id) else { return nil }
        if centered || collectionView.cellForItem(at: path) == nil {
            collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
            collectionView.layoutIfNeeded()
        }
        return (collectionView.cellForItem(at: path) as? TabStackCell)?.previewView
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipe else { return true }
        pendingDragID = nil
        let translation = swipe.translation(in: collectionView)
        guard translation.x < 0, abs(translation.x) > abs(translation.y) * 1.15,
              let path = touchedCard(at: dragOrigin(swipe)),
              let id = dataSource.itemIdentifier(for: path), !closingIDs.contains(id) else { return false }
        pendingDragID = id
        recognitionTranslation = translation.x
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Hosted SwiftUI button/context-menu recognizers must not suppress the collection's
        // horizontal close gesture. Vertical scrolling still waits for this recognizer to fail.
        (gestureRecognizer === swipe || otherGestureRecognizer === swipe)
            && otherGestureRecognizer !== collectionView.panGestureRecognizer
            && gestureRecognizer !== collectionView.panGestureRecognizer
    }

    private func dragOrigin(_ gesture: UIPanGestureRecognizer) -> CGPoint {
        let location = gesture.location(in: collectionView)
        let translation = gesture.translation(in: collectionView)
        return CGPoint(x: location.x - translation.x, y: location.y - translation.y)
    }

    private func touchedCard(at point: CGPoint) -> IndexPath? {
        // Follow UIKit's actual hit-test order, including the cards' z positions and transforms.
        var target = collectionView.hitTest(point, with: nil)
        while let view = target, view !== collectionView {
            if let cell = view as? UICollectionViewCell { return collectionView.indexPath(for: cell) }
            target = view.superview
        }
        return nil
    }

    @objc private func handleSwipe(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let id = pendingDragID, let path = dataSource.indexPath(for: id),
                  let cell = collectionView.cellForItem(at: path) as? TabStackCell else { return }
            pendingDragID = nil
            // A returning card can be caught without teleporting to its destination.
            let currentX = cell.motionView.layer.presentation()?.affineTransform().tx ?? cell.motionView.transform.tx
            animators.removeValue(forKey: id)?.stopAnimation(true)
            // UIKit can reset translation on recognition. Retain the movement that won
            // recognition, including a fast swipe delivered in a single movement event.
            dragStart = currentX + recognitionTranslation - gesture.translation(in: collectionView).x
            cell.motionView.transform = CGAffineTransform(translationX: currentX + recognitionTranslation, y: 0)
            draggedID = id
            draggedCell = cell
            collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        case .changed:
            let distance = dragStart + gesture.translation(in: collectionView).x
            let x = distance < 0 ? distance : 50 * (1 - exp(-distance / 150))
            draggedCell?.motionView.transform = CGAffineTransform(translationX: x, y: 0)
        case .ended, .cancelled:
            guard let id = draggedID, let cell = draggedCell else { return }
            let velocity = gesture.velocity(in: collectionView).x
            let shouldClose = gesture.state == .ended && TabStackMotion.shouldDismiss(
                translation: cell.motionView.transform.tx, velocity: velocity, width: cell.bounds.width)
            draggedID = nil
            draggedCell = nil
            if shouldClose { dismiss(id, velocity: velocity) }
            else { animate(cell: cell, id: id, to: 0, velocity: velocity, closing: false) }
        default: break
        }
    }

    private func cancelDrag() {
        draggedCell?.motionView.transform = .identity
        draggedID = nil
        draggedCell = nil
        for id in Array(animators.keys) where !closingIDs.contains(id) {
            animators.removeValue(forKey: id)?.stopAnimation(true)
            if let path = dataSource.indexPath(for: id) {
                (collectionView.cellForItem(at: path) as? TabStackCell)?.motionView.transform = .identity
            }
        }
    }

    private func dismiss(_ id: UUID, velocity: CGFloat) {
        guard !closingIDs.contains(id), let path = dataSource.indexPath(for: id),
              let cell = collectionView.cellForItem(at: path) as? TabStackCell else { return }
        closingIDs.insert(id)
        let exit = -(view.window?.bounds.width ?? view.bounds.width) - cell.bounds.width
        if stackLayout.reduceMotion {
            animate(cell: cell, id: id, to: exit, velocity: velocity, closing: true)
            return
        }
        animators.removeValue(forKey: id)?.stopAnimation(true)
        let layer = cell.motionView.layer
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: layer.transform)
        let target = CATransform3DMakeTranslation(exit, 0, 0)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = 0.26
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // An explicit animation keeps collection/hosting layout transactions from
        // recapturing an older implicit starting transform during the committed exit.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in self?.finishDismissal(id) }
        }
        layer.transform = target
        layer.add(animation, forKey: "DuoBrowser.dismiss")
        CATransaction.commit()
    }

    func finishPendingDismissals() {
        for id in Array(closingIDs) { finishDismissal(id) }
        for animator in animators.values { animator.stopAnimation(true) }
        animators.removeAll()
    }

    private func finishDismissal(_ id: UUID) {
        guard closingIDs.remove(id) != nil, let close else { return }
        // Retain the committed action, not the controller. Filtering can dismantle
        // the stack before the next run-loop turn; the tab must still close once.
        Task { @MainActor in close(id) }
    }

    private func animate(cell: TabStackCell, id: UUID, to destination: CGFloat, velocity: CGFloat, closing: Bool) {
        animators.removeValue(forKey: id)?.stopAnimation(true)
        // Commit the final finger-driven transform before UIKit captures the animation's
        // starting value. A gesture ending in the same render transaction must not replay
        // an older position when its exit animation is installed.
        CATransaction.flush()
        let delta = destination - cell.motionView.transform.tx
        let initialVelocity = abs(delta) > 1 ? min(12, max(-12, velocity / delta)) : 0
        let timing = UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: initialVelocity, dy: 0))
        // A committed close must continue leftward even when released with a slight rightward velocity.
        let animator = closing
            ? UIViewPropertyAnimator(duration: 0.26, curve: .easeIn)
            : UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
        animator.addAnimations {
            if self.stackLayout.reduceMotion { cell.motionView.alpha = closing ? 0 : 1 }
            else { cell.motionView.transform = CGAffineTransform(translationX: destination, y: 0) }
        }
        animator.addCompletion { [weak self, weak cell] position in
            guard let self, position == .end else { return }
            self.animators[id] = nil
            if closing { self.finishDismissal(id) }
            else { cell?.motionView.transform = .identity }
        }
        animators[id] = animator
        animator.startAnimation()
    }
}
