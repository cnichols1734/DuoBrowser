import SwiftUI
import UIKit

struct BrowserSetup: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var model: BrowserSetupModel
    @State private var scene: UIWindowScene?
    @State private var showingTransferDetails = false
    @State private var occlusions: [CGRect] = []
    @State private var frames: [String: CGRect] = [:]
    @State private var navigationClearance: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    #if DEBUG
    var layoutDidChange: (([String: CGRect]) -> Void)?
    #endif

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: compactHeading ? 20 : 32) {
                        heading
                        content
                        if dynamicTypeSize.isAccessibilitySize { actions }
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .setupFrame("step.\(model.step.rawValue)")
                .id(model.step)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    actions.padding(.top, 16).padding(.bottom, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .systemBackground))
                }
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { navigation.padding(.top, navigationClearance) }
            .ignoresSafeArea(.container, edges: .horizontal)
            .onChange(of: model.step) { _, _ in
                showingTransferDetails = false
                headingFocused = true
            }
            .interactiveDismissDisabled()
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .background {
            SetupSceneReader { currentScene, regions in
                scene = currentScene
                if regions != occlusions { occlusions = regions; updateNavigationClearance(frames) }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        .setupFrame("canvas")
        .coordinateSpace(name: "setup.canvas")
        .onPreferenceChange(SetupFramesKey.self) { value in
            frames = value
            updateNavigationClearance(value)
            #if DEBUG
            layoutDidChange?(value)
            #endif
        }
    }

    private func updateNavigationClearance(_ measured: [String: CGRect]) {
        let baseline = measured.filter { $0.key.hasPrefix("navigation.") }.values.map {
            $0.offsetBy(dx: 0, dy: -navigationClearance)
        }
        let next = SetupLayout.clearance(below: occlusions, controls: baseline)
        if abs(next - navigationClearance) > 0.5 { navigationClearance = next }
    }

    private var navigation: some View {
        ZStack {
            Text("\(model.step.rawValue + 1) of \(BrowserSetupModel.Step.allCases.count)")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityLabel("Step \(model.step.rawValue + 1) of \(BrowserSetupModel.Step.allCases.count)")
                .setupFrame("navigation.progress")
            HStack {
                Button { model.cancel(); advance(back: true) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back").accessibilityIdentifier("setup.back")
                .opacity(model.step == .welcome ? 0 : 1)
                .disabled(model.step == .welcome).accessibilityHidden(model.step == .welcome)
                .setupFrame(model.step == .welcome ? "hidden.back" : "navigation.back")
                Spacer()
                Button("Skip") { finish() }.frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Skip Setup").accessibilityIdentifier("setup.skip")
                    .setupFrame("navigation.skip")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24).padding(.top, 8)
        .background(Color(uiColor: .systemBackground))
    }

    private var compactHeading: Bool {
        model.step == .transfer && model.transferEnabled && !session.privateMode && model.state != .saved
    }

    private var heading: some View {
        VStack(alignment: .center, spacing: compactHeading ? 12 : 16) {
            if !dynamicTypeSize.isAccessibilitySize && !compactHeading {
                Image(systemName: symbol)
                    .rotationEffect(.degrees(model.step == .welcome ? 90 : 0))
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.tint)
                    .frame(height: 64)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(compactHeading ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .setupFrame("heading")
            Text(subtitle)
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var symbol: String {
        switch model.step {
        case .welcome: return "rectangle.expand.vertical"
        case .transfer: return model.state == .saved ? "checkmark.circle" : "square.and.arrow.down"
        case .defaultBrowser: return "link"
        case .tour: return "safari"
        }
    }

    private var title: String {
        switch model.step {
        case .welcome: return "More room\nfor the web"
        case .transfer:
            if model.state == .saved { return "Ready to pick up\nwhere you left off" }
            return model.state == .review ? "Choose what to keep" : "Bring your\nsaved pages"
        case .defaultBrowser: return "Open links here"
        case .tour: return "Within easy reach"
        }
    }

    private var subtitle: String {
        switch model.step {
        case .welcome: return "DuoBrowser gives your pages more space, with the controls close at hand."
        case .transfer:
            if session.privateMode { return "Switch to regular browsing to bring your saved pages into your library." }
            if model.state == .review { return "Add the things you want. Your originals stay in Safari." }
            if model.state == .saved { return "Your selected pages are in your library." }
            return model.transferEnabled
                ? "Bring bookmarks, history, and Reading List from Safari. You’ll review everything before saving."
                : "Safari transfer isn’t available yet. You can start browsing and add bookmarks along the way."
        case .defaultBrowser:
            return model.transferEnabled
                ? "Make DuoBrowser your default to open web links from other apps here."
                : "Default-browser setup isn’t available yet. You can still open any website in DuoBrowser."
        case .tour: return "A few familiar controls, right at the bottom."
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            if !dynamicTypeSize.isAccessibilitySize { browserControls }
            Text("Set up now, or skip and start browsing")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .transfer:
            transfer
        case .defaultBrowser:
            if model.transferEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    instruction("1", title: "Open Default Apps", detail: "We’ll take you to Settings")
                    instruction("2", title: "Choose Browser App", detail: "Then select DuoBrowser")
                }
                if let message = model.settingsMessage {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .tour:
            VStack(alignment: .leading, spacing: 24) {
                feature("Search", icon: "magnifyingglass", detail: "Tap the address bar. Tap it again to bring back hidden controls.")
                feature("Tabs", icon: "square.on.square", detail: "Switch pages, open a new tab, or choose Private.")
                feature("Page options", icon: "line.3.horizontal.decrease", detail: "Open Website Settings to use a page’s original layout.")
                feature("Library", icon: "book", detail: "Find bookmarks, history, and your Reading List.")
            }
        }
    }

    // A static illustration of the browser's real control arrangement, not a second toolbar.
    private var browserControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search the web").font(.subheadline)
            }
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            Image(systemName: "square.on.square").frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
        .font(.body)
        .padding(.vertical, 16)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var transfer: some View {
        if !session.privateMode && model.transferEnabled {
            VStack(alignment: .leading, spacing: 20) {
                if model.busy {
                    ProgressView(model.state == .receiving ? "Receiving \(model.received) items…" : "Waiting for Safari…")
                        .frame(maxWidth: .infinity)
                } else if model.state != .saved {
                    transferChoices
                    if model.state == .review && !model.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Favorites folder", selection: $model.favoriteFolder) {
                                Text("Choose a folder").tag("")
                                ForEach(model.folders, id: \.id) { folder in Text(verbatim: folder.title).tag(folder.id) }
                            }.pickerStyle(.menu)
                            Text("Pages in this folder appear on your start page.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let message = model.message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("setup.import.status")
                }
                if model.state != .saved {
                    DisclosureGroup("About Safari transfer", isExpanded: $showingTransferDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Favorites travel with bookmarks. Include Bookmarks in Safari’s transfer screen, then choose your Favorites folder here.")
                            Text("Passwords, signed-in sessions, open tabs, extensions, and offline downloads aren’t transferred. Imported data stays on this device.")
                        }
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.subheadline)
                }
            }
        }
    }

    private var transferChoices: some View {
        VStack(spacing: 0) {
            transferChoice("Bookmarks", selection: $model.choices.bookmarks)
            Divider()
            transferChoice("Favorites", selection: $model.choices.favorites)
            Divider()
            transferChoice("History", selection: $model.choices.history)
            Divider()
            transferChoice("Reading List", selection: $model.choices.readingList)
        }
    }

    private func transferChoice(_ title: String, selection: Binding<Bool>) -> some View {
        Toggle(title, isOn: selection).padding(.vertical, 12)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: primaryAction) {
                Text(primaryTitle).font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(primaryDisabled)
            .accessibilityIdentifier("setup.continue")
            .setupFrame("primary")
            if model.step == .transfer && model.transferEnabled && model.state != .saved && !session.privateMode && !model.busy {
                Button(model.state == .review ? "Don’t Import" : "Not Now") { model.cancel(); advance() }
                    .frame(minHeight: 44)
            } else if model.step == .defaultBrowser && model.transferEnabled {
                Button("Continue") { advance() }.frame(minHeight: 44)
            }
        }
        .frame(maxWidth: 440)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 0 : 32)
    }

    private var primaryTitle: String {
        if model.step == .welcome { return "Get Started" }
        if model.step == .tour { return "Start Browsing" }
        if model.step == .defaultBrowser && model.transferEnabled { return "Open Settings" }
        guard model.step == .transfer else { return "Continue" }
        if model.busy { return "Cancel Transfer" }
        if model.state == .review { return "Add Selected Data" }
        if model.state == .saved { return "Continue" }
        return model.transferEnabled && !session.privateMode ? "Continue with Safari" : "Continue"
    }

    private var primaryDisabled: Bool {
        guard model.step == .transfer, model.transferEnabled, !session.privateMode, !model.busy, model.state != .saved else { return false }
        if !model.choices.hasSelection { return true }
        if model.state == .review {
            return model.choices.favorites && !model.choices.bookmarks && !model.choices.history && !model.choices.readingList && model.favoriteFolder.isEmpty
        }
        return scene == nil
    }

    private func primaryAction() {
        if model.step == .tour { finish(); return }
        if model.step == .defaultBrowser && model.transferEnabled { model.openDefaultSettings(); return }
        if model.step == .transfer {
            if model.busy { model.cancel(); return }
            if model.state == .review { model.save(into: session); return }
            if model.state != .saved && model.transferEnabled && !session.privateMode { model.request(scene: scene); return }
            model.cancel()
        }
        advance()
    }

    private func advance(back: Bool = false) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            if back { model.back() } else { model.next() }
        }
    }

    private func feature(_ title: String, icon: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint)
                    .frame(width: 28, height: 28).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }

    private func instruction(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number).font(.body.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }

    private func finish() { model.finish(); session.showingSetup = false }
}

private struct SetupSceneReader: UIViewRepresentable {
    var update: (UIWindowScene?, [CGRect]) -> Void
    func makeUIView(context: Context) -> SceneView { let view = SceneView(); view.update = update; return view }
    func updateUIView(_ view: SceneView, context: Context) { view.update = update; view.setNeedsLayout() }
    final class SceneView: UIView {
        var update: ((UIWindowScene?, [CGRect]) -> Void)?
        private weak var lastScene: UIWindowScene?
        private var lastRegions: [CGRect]?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            setNeedsLayout()
        }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            let scene = window?.windowScene
            // UIKit's frame already includes the interactive-content margins.
            let regions = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            guard scene !== lastScene || regions != lastRegions else { return }
            lastScene = scene; lastRegions = regions
            DispatchQueue.main.async { [weak self] in self?.update?(scene, regions) }
        }
    }
}

enum SetupLayout {
    static func clearance(below regions: [CGRect], controls: [CGRect]) -> CGFloat {
        guard let top = controls.map(\.minY).min() else { return 0 }
        var clearance: CGFloat = 0
        // Clearing a later bottom edge also clears every previously examined region,
        // including when individual controls have different vertical positions.
        for region in regions.filter({ !$0.isNull && !$0.isInfinite && !$0.isEmpty }).sorted(by: { $0.maxY < $1.maxY }) {
            if controls.contains(where: { $0.offsetBy(dx: 0, dy: clearance).intersects(region) }) {
                clearance = max(clearance, region.maxY + 8 - top)
            }
        }
        return clearance
    }
}

private struct SetupFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, latest in latest }) }
}

private extension View {
    func setupFrame(_ name: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: SetupFramesKey.self, value: [name: geometry.frame(in: .named("setup.canvas"))])
        })
    }
}
