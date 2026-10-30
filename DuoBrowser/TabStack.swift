import SwiftUI
import UIKit

/// One scroll position drives layout, hit testing and snapping. No delayed per-card animations.
struct TabStack<Content: View>: UIViewControllerRepresentable {
    let tabs: [BrowserModel]
    let selectedID: UUID
    let reduceMotion: Bool
    let close: (UUID) -> Void
    @ViewBuilder var content: (BrowserModel, @escaping () -> Void) -> Content

    func makeUIViewController(context: Context) -> TabStackController { TabStackController() }

    func updateUIViewController(_ controller: TabStackController, context: Context) {
        controller.update(tabs: tabs, selectedID: selectedID, reduceMotion: reduceMotion, close: close) { tab, dismiss in
            AnyView(content(tab, dismiss))
        }
    }
}

/// Continuous position AND velocity at the foreground boundary. Further-left cards progressively
/// compress into the stack; they never stop moving or reverse order. This is our curve, not an
/// implementation detail of Apple's private app switcher.
enum TabStackMotion {
    nonisolated static func position(_ distance: CGFloat, stride: CGFloat, reduceMotion: Bool) -> CGFloat {
        guard stride > 0, distance.isFinite else { return 0 }
        guard !reduceMotion, distance < 0 else { return distance }
        let reach = stride * 0.8
        return distance * 0.22 + reach * 0.78 * tanh(distance / reach)
    }

    nonisolated static func target(proposed: CGFloat, stride: CGFloat, count: Int) -> CGFloat {
        guard stride > 0, count > 0, proposed.isFinite else { return 0 }
        return min(CGFloat(count - 1), max(0, (proposed / stride).rounded())) * stride
    }

    nonisolated static func shouldDismiss(translation: CGFloat, velocity: CGFloat, height: CGFloat) -> Bool {
        // A downward reversal cancels a flick. Project momentum using the native fast deceleration rate.
        guard translation < -24, velocity < 120 else { return false }
        let projected = translation + velocity * 0.099
        return -projected > height * 0.24
    }
}

final class TabStackLayout: UICollectionViewLayout {
    var reduceMotion = false
    var pendingOffset: CGFloat?
    var cardWidth: CGFloat {
        let size = collectionView?.bounds.size ?? .zero
        return min(300, max(160, min(size.width * 0.67, (size.height - 56) * 0.68)))
    }
    var stride: CGFloat { cardWidth * 0.78 }
    private var count: Int { collectionView?.numberOfItems(inSection: 0) ?? 0 }

    override var collectionViewContentSize: CGSize {
        CGSize(width: (collectionView?.bounds.width ?? 0) + CGFloat(max(0, count - 1)) * stride,
               height: collectionView?.bounds.height ?? 0)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool { true }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let collectionView, count > 0 else { return [] }
        let focus = Int(floor(collectionView.contentOffset.x / stride))
        // The compressed tail can expose several cards; keep the work bounded even for hundreds of tabs.
        let lower = max(0, focus - 8), upper = min(count - 1, focus + 3)
        guard lower <= upper else { return [] }
        return (lower...upper).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let collectionView, indexPath.item < count else { return nil }
        let offset = collectionView.contentOffset.x
        let distance = CGFloat(indexPath.item) * stride - offset
        let projected = TabStackMotion.position(distance, stride: stride, reduceMotion: reduceMotion)
        let depth = reduceMotion ? 0 : max(0, -distance / stride)
        let scale = 1 - 0.07 * (1 - exp(-depth * depth * 0.8))
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.size = CGSize(width: cardWidth, height: cardWidth / 0.68 + 28)
        attributes.center = CGPoint(x: offset + collectionView.bounds.width * 0.5 + projected,
                                    y: collectionView.bounds.height * 0.5)
        attributes.transform = CGAffineTransform(scaleX: scale, y: scale)
        attributes.zIndex = indexPath.item
        return attributes
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint,
                                      withScrollingVelocity velocity: CGPoint) -> CGPoint {
        // UIKit already projects the release velocity. Snap that destination, not the finger's last position.
        CGPoint(x: TabStackMotion.target(proposed: proposedContentOffset.x, stride: stride, count: count), y: 0)
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard let pendingOffset else { return proposedContentOffset }
        return CGPoint(x: TabStackMotion.target(proposed: pendingOffset, stride: stride, count: count), y: 0)
    }
}

final class TabStackCell: UICollectionViewCell {
    var representedID: UUID?
    // UIKit owns contentView's transform. Keep interactive motion on our own container.
    let motionView = UIView()
    private var hostedView: (UIView & UIContentView)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        motionView.frame = contentView.bounds
        motionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(motionView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ configuration: UIHostingConfiguration<AnyView, EmptyView>) {
        if let hostedView { hostedView.configuration = configuration }
        else {
            let hosted = configuration.makeContentView()
            hosted.frame = motionView.bounds
            hosted.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            motionView.addSubview(hosted)
            hostedView = hosted
        }
    }
}

final class TabStackController: UIViewController, UIGestureRecognizerDelegate {
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
    private weak var draggedCell: TabStackCell?
    private var dragStart: CGFloat = 0
    private var animators: [UUID: UIViewPropertyAnimator] = [:]
    private var closingIDs: Set<UUID> = []

    override func loadView() {
        view = collectionView
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.decelerationRate = .fast
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.clipsToBounds = false
        collectionView.register(TabStackCell.self, forCellWithReuseIdentifier: "tab")
        dataSource = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: collectionView) { [weak self] collection, path, id in
            guard let self, let tab = self.tabs.first(where: { $0.id == id }) else { return nil }
            guard let cell = collection.dequeueReusableCell(withReuseIdentifier: "tab", for: path) as? TabStackCell else { return nil }
            if cell.representedID != id {
                if let previous = cell.representedID {
                    self.animators.removeValue(forKey: previous)?.stopAnimation(true)
                    // A fast horizontal fling may recycle a departing card. Complete its committed close
                    // on the next turn, outside UIKit's cell-provider callback, without moving the new card.
                    if self.closingIDs.contains(previous) {
                        Task { @MainActor [weak self] in self?.finishDismissal(previous) }
                    }
                }
                cell.motionView.transform = .identity
                cell.motionView.alpha = 1
                cell.representedID = id
            }
            cell.configure(UIHostingConfiguration {
                self.makeCard?(tab, { [weak self] in self?.dismiss(id, velocity: 0) }) ?? AnyView(EmptyView())
            }.margins(.all, 0))
            cell.motionView.layer.shadowColor = UIColor.black.cgColor
            cell.motionView.layer.shadowOpacity = 0.14
            cell.motionView.layer.shadowRadius = 14
            cell.motionView.layer.shadowOffset = CGSize(width: -5, height: 3)
            cell.motionView.layer.shadowPath = UIBezierPath(roundedRect: CGRect(x: 0, y: 28,
                width: self.stackLayout.cardWidth, height: self.stackLayout.cardWidth / 0.68), cornerRadius: 18).cgPath
            return cell
        }
        swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.delegate = self
        swipe.maximumNumberOfTouches = 1
        collectionView.addGestureRecognizer(swipe)
        collectionView.panGestureRecognizer.require(toFail: swipe)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The overview can scroll vertically on compact displays; a card gesture wins only when vertical.
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView { scroll.panGestureRecognizer.require(toFail: swipe) }
            ancestor = current.superview
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard collectionView.bounds.width > 0, collectionView.bounds.size != previousSize else { return }
        let oldStride = min(300, max(160, min(previousSize.width * 0.67, (previousSize.height - 56) * 0.68))) * 0.78
        let index = previousSize == .zero ? 0 : (collectionView.contentOffset.x / oldStride).rounded()
        previousSize = collectionView.bounds.size
        stackLayout.invalidateLayout()
        let focus = initialFocus.flatMap { id in tabs.firstIndex { $0.id == id } }.map { CGFloat($0) } ?? index
        initialFocus = nil
        collectionView.contentOffset = CGPoint(x: TabStackMotion.target(proposed: focus * stackLayout.stride,
            stride: stackLayout.stride, count: tabs.count), y: 0)
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
        guard oldIDs != ids else { return }
        let oldIndex = Int((collectionView.contentOffset.x / stackLayout.stride).rounded())
        let focusedID = oldIDs.indices.contains(oldIndex) ? oldIDs[oldIndex] : nil
        let focus = focusedID.flatMap { ids.firstIndex(of: $0) }
            ?? (oldIDs.isEmpty || !ids.contains(where: oldIDs.contains) ? ids.firstIndex(of: selectedID) : nil)
            ?? min(oldIndex, max(0, ids.count - 1))
        cancelDrag()
        for removed in Set(oldIDs).subtracting(ids) {
            animators.removeValue(forKey: removed)?.stopAnimation(true)
            closingIDs.remove(removed)
        }
        self.tabs = tabs
        if previousSize == .zero { initialFocus = selectedID }
        stackLayout.pendingOffset = CGFloat(focus) * stackLayout.stride
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        if selectionChanged { snapshot.reconfigureItems(ids.filter(oldIDs.contains)) }
        dataSource.apply(snapshot, animatingDifferences: !reduceMotion && !oldIDs.isEmpty) { [weak self] in
            self?.stackLayout.pendingOffset = nil
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipe else { return true }
        let velocity = swipe.velocity(in: collectionView)
        guard abs(velocity.y) > abs(velocity.x) * 1.15,
              let path = touchedCard(at: swipe.location(in: collectionView)),
              let id = dataSource.itemIdentifier(for: path), !closingIDs.contains(id) else { return false }
        return true
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
            guard let path = touchedCard(at: gesture.location(in: collectionView)),
                  let id = dataSource.itemIdentifier(for: path), let cell = collectionView.cellForItem(at: path) as? TabStackCell else { return }
            // A returning card can be caught without teleporting to its destination.
            let currentY = cell.motionView.layer.presentation()?.affineTransform().ty ?? cell.motionView.transform.ty
            animators.removeValue(forKey: id)?.stopAnimation(true)
            cell.motionView.transform = CGAffineTransform(translationX: 0, y: currentY)
            draggedID = id
            draggedCell = cell
            dragStart = currentY
            collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        case .changed:
            let distance = dragStart + gesture.translation(in: collectionView).y
            let y = distance < 0 ? distance : 50 * (1 - exp(-distance / 150))
            draggedCell?.motionView.transform = CGAffineTransform(translationX: 0, y: y)
        case .ended, .cancelled:
            guard let id = draggedID, let cell = draggedCell else { return }
            let velocity = gesture.velocity(in: collectionView).y
            let shouldClose = gesture.state == .ended && TabStackMotion.shouldDismiss(
                translation: cell.motionView.transform.ty, velocity: velocity, height: cell.bounds.height)
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
        let exit = -(view.window?.bounds.height ?? view.bounds.height) - cell.bounds.height
        animate(cell: cell, id: id, to: exit, velocity: velocity, closing: true)
    }

    private func finishDismissal(_ id: UUID) {
        guard closingIDs.remove(id) != nil else { return }
        close?(id)
    }

    private func animate(cell: TabStackCell, id: UUID, to destination: CGFloat, velocity: CGFloat, closing: Bool) {
        animators.removeValue(forKey: id)?.stopAnimation(true)
        let delta = destination - cell.motionView.transform.ty
        let initialVelocity = abs(delta) > 1 ? min(12, max(-12, velocity / delta)) : 0
        let timing = UISpringTimingParameters(dampingRatio: 1, initialVelocity: CGVector(dx: 0, dy: initialVelocity))
        // A committed close must continue upward even when released with a slight downward velocity.
        let animator = closing
            ? UIViewPropertyAnimator(duration: 0.26, curve: .easeIn)
            : UIViewPropertyAnimator(duration: 0.32, timingParameters: timing)
        animator.addAnimations {
            if self.stackLayout.reduceMotion { cell.motionView.alpha = closing ? 0 : 1 }
            else { cell.motionView.transform = CGAffineTransform(translationX: 0, y: destination) }
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
