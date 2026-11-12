import SwiftUI
import UIKit

@MainActor
final class RedditLinkRouting: ObservableObject {
    static let preferenceKey = "browser.redditLinks"
    private let storage: UserDefaults
    @Published var preference: RedditLinkPreference {
        didSet { storage.set(preference.rawValue, forKey: Self.preferenceKey) }
    }
    // Injectable system boundary for isolated native checks; no installed-app inventory is stored.
    // iOS 27 deprecates this probe, but choosing among installed apps requires it without launching them.
    var canOpen: (URL) -> Bool = { UIApplication.shared.canOpenURL($0) }
    var open: @MainActor (URL, @escaping @MainActor @Sendable (Bool) -> Void) -> Void = { url, completion in
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
    var apolloAvailable: Bool { canOpen(URL(string: "apollo://reddit.com")!) }

    init(storage: UserDefaults) {
        self.storage = storage
        preference = storage.string(forKey: Self.preferenceKey).flatMap(RedditLinkPreference.init(rawValue:)) ?? .chooseOnce
    }

    /// true means cancel the web navigation; false means continue its original request.
    func route(_ url: URL, isPrivate: Bool, isCurrent: @escaping @MainActor @Sendable () -> Bool,
               choose: ([RedditLinkPreference], String, @escaping (RedditLinkPreference?) -> Void) -> Void,
               completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard preference != .browser, let target = RedditLinks.apolloURL(url), canOpen(target) else {
            completion(false); return
        }
        let startingPreference = preference
        let selected: (RedditLinkPreference?) -> Void = { [weak self] choice in
            guard let self, isCurrent(), self.preference == startingPreference, let choice else { completion(true); return }
            if !isPrivate && startingPreference == .chooseOnce { self.preference = choice }
            guard choice == .apollo else { completion(false); return }
            self.open(target) { opened in completion(opened || !isCurrent()) }
        }
        if preference == .apollo && !isPrivate { selected(.apollo) }
        else {
            let message = isPrivate
                ? "Opening another app shares this link outside Private Browsing. This choice won’t be saved."
                : preference == .chooseOnce
                    ? "Your choice will be remembered. Change it in Settings → Open Links → Reddit."
                    : "Choose where to open this Reddit link."
            choose([.apollo, .browser], message, selected)
        }
    }
}

struct BrowserLinkSettings: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var routing: RedditLinkRouting
    @Environment(\.dismiss) private var dismiss
    @State private var apolloAvailable = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Block Ads & Trackers", isOn: $session.adBlockingEnabled)
                } header: {
                    Text("Ad Blocking")
                } footer: {
                    Text("Built-in protection blocks common ad and tracking services. It doesn’t block every ad. Changes apply to new requests in all tabs; reload a page to refresh its content. Website Protection manages exceptions for individual sites.")
                }
                Section("Open Links") {
                    Picker("Reddit", selection: $routing.preference) {
                        ForEach(RedditLinkPreference.allCases, id: \.self) { choice in
                            Text(choice == .apollo && !apolloAvailable ? "Apollo Reborn (Unavailable)" : choice.title)
                                .tag(choice)
                                .disabled(choice == .apollo && !apolloAvailable)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Text("Reddit links you tap can open in Apollo Reborn. If the app is unavailable, links open in DuoBrowser.")
                    Text("Private tabs ask before opening another app. Typed addresses and links opened from other apps stay in DuoBrowser.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { apolloAvailable = routing.apolloAvailable }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                apolloAvailable = routing.apolloAvailable
            }
        }
    }
}
