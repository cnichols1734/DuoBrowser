import SwiftUI
import UIKit

struct BrowserSetup: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var model: BrowserSetupModel
    @State private var scene: UIWindowScene?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Step \(model.step.rawValue + 1) of 4")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                    content
                    if dynamicTypeSize.isAccessibilitySize { footer }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(24).frame(maxWidth: .infinity)
            }
            .id(model.step)
            .safeAreaInset(edge: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize { footer }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Set Up DuoBrowser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip Setup") { finish() }.accessibilityIdentifier("setup.skip")
                }
            }
            .background { SetupSceneReader { scene = $0 }.frame(width: 0, height: 0) }
            .onChange(of: model.step) { _, _ in headingFocused = true }
            .interactiveDismissDisabled()
        }
    }

    private var title: String {
        switch model.step {
        case .welcome: return "Make yourself at home."
        case .transfer: return model.state == .review ? "Choose what to keep." : "Bring your browsing with you."
        case .defaultBrowser: return "Open links in DuoBrowser."
        case .tour: return "You’re ready to browse."
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            Image(systemName: "safari").font(.system(size: 64, weight: .light)).foregroundStyle(.tint).accessibilityHidden(true)
            Text("Bring over your saved pages, choose your default browser, and get to know the controls.")
                .font(.title3)
            Text("Every step is optional. You can return here from Page options → Set Up DuoBrowser.")
                .foregroundStyle(.secondary)
        case .transfer:
            transfer
        case .defaultBrowser:
            feature("Links open here", icon: "link", detail: "Choose DuoBrowser as your default to open web links from other apps here.")
            if model.transferEnabled {
                Button("Open Default Apps Settings") { model.openDefaultSettings() }
                    .buttonStyle(.bordered).controlSize(.large)
                Text(model.settingsMessage ?? "In Settings, choose Browser App, then DuoBrowser. This step is optional.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Default-browser selection isn’t available in this build yet. You can keep browsing and set it up in a supported update.")
                    .foregroundStyle(.secondary)
            }
        case .tour:
            feature("Search or enter a website", icon: "magnifyingglass", detail: "Tap the address bar at the bottom. Tap the small address pill to bring the controls back while reading.")
            feature("Keep your tabs together", icon: "square.on.square", detail: "Tap Tabs to switch pages or open a new tab. Choose Private in the tab overview for tabs that aren’t saved.")
            feature("Choose how a page fits", icon: "line.3.horizontal.decrease", detail: "Open Page options → Website Settings. Choose Original Layout whenever you prefer the website’s own layout.")
            feature("Find your saved pages", icon: "book", detail: "Your bookmarks, folders, history, and Reading List are in Library. Favorites appear on the start page.")
        }
    }

    private var transfer: some View {
        VStack(alignment: .leading, spacing: 20) {
            if session.privateMode {
                Text("Switch to regular browsing to transfer data. Imported pages are saved in your regular library.")
            } else {
                if model.state == .review {
                    Text("Review the data received from your browser. Choose what to keep in DuoBrowser.")
                } else if model.state == .saved {
                    Label("Transfer saved", systemImage: "checkmark.circle")
                } else if model.transferEnabled {
                    Text("Choose Safari in the system transfer screen. Your Safari data stays in Safari, and you review the copy here before saving it.")
                } else {
                    Label("Direct transfer isn’t available in this build yet.", systemImage: "info.circle")
                    Text("Continue setup now. You can return to this step when a supported update is available.")
                        .foregroundStyle(.secondary)
                }
                if model.state != .saved && !model.busy {
                    VStack(spacing: 16) {
                        Toggle("Bookmarks", isOn: $model.choices.bookmarks)
                        Toggle("Favorites", isOn: $model.choices.favorites)
                        Toggle("History", isOn: $model.choices.history)
                        Toggle("Reading List", isOn: $model.choices.readingList)
                    }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 20))
                    if model.state != .review {
                        Text("Favorites travel with bookmarks. Include Bookmarks in Safari’s transfer screen; you can choose your Favorites folder here afterward.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if model.busy {
                    ProgressView(model.state == .receiving ? "Receiving data… \(model.received) items" : "Waiting for the system transfer…")
                } else if model.state == .review {
                    if !model.folders.isEmpty {
                        Picker("Your Favorites folder", selection: $model.favoriteFolder) {
                            Text("No Favorites folder").tag("")
                            ForEach(model.folders, id: \.id) { folder in Text(verbatim: folder.title).tag(folder.id) }
                        }.pickerStyle(.menu)
                        Text("Choose the folder you used for Favorites in Safari. Its pages will appear on your start page if Favorites is selected.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Received: \(model.batch?.bookmarks.values.filter { !$0.isFolder }.count ?? 0) bookmarks · \(model.batch?.history.count ?? 0) history · \(model.batch?.readingList.count ?? 0) Reading List")
                    Button("Discard Transfer") { model.cancel() }.frame(minHeight: 44)
                }
                if let message = model.message {
                    Text(message).foregroundStyle(model.state == .failed ? .primary : .secondary)
                        .accessibilityIdentifier("setup.import.status")
                }
                Text("Passwords, signed-in sessions, open tabs, extensions, and offline Reading List downloads aren’t transferred. Imported data stays on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(primaryDisabled)
                .frame(maxWidth: .infinity).accessibilityIdentifier("setup.continue")
            if model.step == .transfer && model.transferEnabled && model.state != .saved && !session.privateMode {
                Button("Not Now") { model.cancel(); model.next() }.frame(minHeight: 44)
            }
            if model.step != .welcome {
                Button("Back") { model.cancel(); model.back() }.frame(minHeight: 44)
            }
        }
        .frame(maxWidth: 560).padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private var primaryTitle: String {
        if model.step == .tour { return "Start Browsing" }
        guard model.step == .transfer else { return "Continue" }
        if model.busy { return "Cancel Transfer" }
        if model.state == .review { return "Add Selected Data" }
        if model.state == .saved { return "Continue" }
        return model.transferEnabled && !session.privateMode ? "Continue with Safari" : "Not Now"
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
        if model.step == .transfer {
            if model.busy { model.cancel(); return }
            if model.state == .review { model.save(into: session); return }
            if model.state != .saved && model.transferEnabled && !session.privateMode { model.request(scene: scene); return }
            model.cancel()
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.next() }
    }

    private func feature(_ title: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private func finish() { model.finish(); session.showingSetup = false }
}

private struct SetupSceneReader: UIViewRepresentable {
    var update: (UIWindowScene?) -> Void
    func makeUIView(context: Context) -> SceneView { let view = SceneView(); view.update = update; return view }
    func updateUIView(_ view: SceneView, context: Context) { view.update = update }
    final class SceneView: UIView {
        var update: ((UIWindowScene?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            let scene = window?.windowScene
            DispatchQueue.main.async { [weak self] in self?.update?(scene) }
        }
    }
}
