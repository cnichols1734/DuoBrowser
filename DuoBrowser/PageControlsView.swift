import SwiftUI

enum PageControlsAction {
    case share, save, find, reader, protection, websiteSettings
    case newTab, forward, pin, workspaces, library, downloads, settings
    #if DEBUG
    case regions, fixture
    #endif

    var requiresCurrentDocument: Bool {
        switch self {
        case .share, .save, .find, .reader, .protection, .websiteSettings, .forward: return true
        default: return false
        }
    }
}

/// A page may navigate while its controls are open. Never apply a queued page action to the next document.
@MainActor
struct PageControlsRequest {
    let action: PageControlsAction
    let browserID: UUID
    let documentID: UUID
    let isPrivate: Bool

    init(action: PageControlsAction, browser: BrowserModel) {
        self.action = action
        browserID = browser.id
        documentID = browser.documentGeneration
        isPrivate = browser.isPrivate
    }

    func matches(_ browser: BrowserModel) -> Bool {
        browser.id == browserID && browser.isPrivate == isPrivate
            && (!action.requiresCurrentDocument || browser.documentGeneration == documentID)
    }
}

struct PageControlsView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    let perform: (PageControlsAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasPage: Bool { browser.restorationURL != nil }
    private var protectionStatus: String {
        if !session.adBlockingEnabled { return "Off in Settings" }
        if !browser.blockAds { return "Off for this website" }
        return browser.blockingStatus
    }
    private var layoutStatus: String {
        [browser.originalPageLayout ? "Original layout" : "Camera-aware layout",
         browser.desktopSite ? "Desktop website" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if hasPage {
                        pageActions
                        VStack(spacing: 0) {
                            destination("Website Settings", subtitle: layoutStatus, symbol: "globe", action: .websiteSettings)
                            Divider().padding(.leading, 40)
                            destination("Website Protection", subtitle: protectionStatus,
                                        symbol: session.adBlockingEnabled && browser.blockAds ? "checkmark.shield" : "shield.slash",
                                        action: .protection)
                        }
                    }
                    tabActions
                    browserActions
                    #if DEBUG
                    Menu("Developer", systemImage: "hammer") {
                        Button(session.showRegions ? "Hide Reserved Regions" : "Show Reserved Regions") { perform(.regions) }
                        Button("Open Test Page") { perform(.fixture) }
                    }
                    .font(.footnote).foregroundStyle(.secondary).frame(minHeight: 44)
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(hasPage ? 620 : 390), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: hasPage ? browser.title : "Start Page")
                    .font(.headline).lineLimit(2)
                if hasPage {
                    Text(verbatim: browser.siteName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if browser.isPrivate {
                    Label("Private Browsing", systemImage: "hand.raised")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Done")
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
        .frame(maxWidth: 668).frame(maxWidth: .infinity)
    }

    private var pageActions: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    textAction("Share", symbol: "square.and.arrow.up", action: .share)
                    textAction("Save Page", symbol: "bookmark", action: .save)
                    textAction("Find on Page", symbol: "doc.text.magnifyingglass", action: .find)
                    textAction(browser.readerLoading ? "Preparing Reader…" : "Reader", symbol: "doc.richtext", action: .reader,
                               disabled: browser.isLoading || browser.readerLoading)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    quickAction("Share", symbol: "square.and.arrow.up", action: .share)
                    quickAction("Save", symbol: "bookmark", action: .save).accessibilityLabel("Save Page")
                    quickAction("Find", symbol: "doc.text.magnifyingglass", action: .find).accessibilityLabel("Find on Page")
                    quickAction(browser.readerLoading ? "Preparing…" : "Reader", symbol: "doc.richtext", action: .reader,
                                disabled: browser.isLoading || browser.readerLoading)
                }
            }
        }
    }

    private var tabActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Tab").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    textAction("New Tab", symbol: "plus", action: .newTab)
                    textAction("Forward", symbol: "chevron.forward", action: .forward, disabled: !browser.canGoForward)
                    textAction(browser.isPinned ? "Unpin Tab" : "Pin Tab", symbol: browser.isPinned ? "pin.slash" : "pin", action: .pin)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    quickAction("New Tab", symbol: "plus", action: .newTab)
                    quickAction("Forward", symbol: "chevron.forward", action: .forward, disabled: !browser.canGoForward)
                    quickAction(browser.isPinned ? "Unpin" : "Pin Tab", symbol: browser.isPinned ? "pin.slash" : "pin", action: .pin)
                }
            }
        }
    }

    private var browserActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.bottom, 8)
            Text("Browser").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    textAction("Library", symbol: "book", action: .library)
                    PageControlsDownloadAction(manager: browser.downloads, compact: false) { perform(.downloads) }
                    textAction("Workspaces", symbol: "square.stack", action: .workspaces)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    quickAction("Library", symbol: "book", action: .library)
                    PageControlsDownloadAction(manager: browser.downloads, compact: true) { perform(.downloads) }
                    quickAction("Workspaces", symbol: "square.stack", action: .workspaces)
                }
            }
            textAction("Settings", symbol: "gearshape", action: .settings)
        }
    }

    private func destination(_ title: String, subtitle: String, symbol: String, action: PageControlsAction) -> some View {
        Button { perform(action) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium))
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine)
    }

    private func quickAction(_ title: String, symbol: String, action: PageControlsAction, disabled: Bool = false) -> some View {
        PageControlsQuickAction(title: title, symbol: symbol, disabled: disabled) { perform(action) }
    }

    private func textAction(_ title: String, symbol: String, action: PageControlsAction, disabled: Bool = false) -> some View {
        Button { perform(action) } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.primary).disabled(disabled)
    }
}

private struct PageControlsQuickAction: View {
    let title: String
    let symbol: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 23, weight: .regular)).frame(height: 30)
                Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .top).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.primary).disabled(disabled)
    }
}

private struct PageControlsDownloadAction: View {
    @ObservedObject var manager: BrowserDownloads
    let compact: Bool
    let action: () -> Void
    private var label: String { manager.activeCount > 0 ? "Downloads, \(manager.activeCount) active" : "Downloads" }

    var body: some View {
        Group {
            if compact {
                PageControlsQuickAction(title: "Downloads", symbol: "arrow.down.circle", action: action)
                    .overlay(alignment: .topTrailing) {
                        if manager.activeCount > 0 || manager.hasUnseenDownloads {
                            Circle().fill(.tint).frame(width: 6, height: 6).padding(.trailing, 14).accessibilityHidden(true)
                        }
                    }
            } else {
                Button(action: action) {
                    Label(manager.activeCount > 0 ? "Downloads (\(manager.activeCount) active)" : "Downloads", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.primary)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(manager.hasUnseenDownloads ? "New downloads" : "")
    }
}
