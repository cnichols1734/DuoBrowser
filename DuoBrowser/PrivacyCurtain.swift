import Combine
import UIKit

/// Cover all app windows before the system captures task-switcher snapshots, including sheets.
@MainActor
final class PrivacyCurtain {
    private var subscriptions: Set<AnyCancellable> = []
    private var covers: [UIView] = []
    init() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.cover() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.uncover() } }.store(in: &subscriptions)
    }
    private func cover() {
        uncover()
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !window.isHidden {
                let cover = UIView(frame: window.bounds)
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.backgroundColor = .systemBackground
                let label = UILabel()
                label.text = "DuoBrowser"
                label.font = .preferredFont(forTextStyle: .title2)
                label.textAlignment = .center
                label.frame = cover.bounds
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.addSubview(label)
                window.addSubview(cover)
                covers.append(cover)
            }
        }
    }
    private func uncover() { covers.forEach { $0.removeFromSuperview() }; covers.removeAll() }
}
