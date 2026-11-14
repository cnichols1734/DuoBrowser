import SwiftUI
import UIKit

/// Presentation only: a failed first load has a useful address without becoming a
/// committed website, permission scope or persistent restoration destination.
@MainActor
struct BrowserAddressIdentity {
    let siteName: String
    let editingAddress: String
    let transportLabel: String

    init(browser: BrowserModel) {
        if browser.failureCoversPage, let target = browser.loadFailure?.targetURL, let host = target.host {
            siteName = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            editingAddress = target.absoluteString
            transportLabel = target.scheme == "http" ? "Not Secure · " : ""
        } else {
            siteName = browser.siteName
            editingAddress = browser.address
            transportLabel = browser.transportLabel
        }
    }
}

struct BrowserRecoveryView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    let fillsPage: Bool
    let editAddress: () -> Void
    var maximumHeight: CGFloat = 360
    @State private var savedCopyError: String?
    #if DEBUG
    var registerElementProbe: ((String, UIView) -> Void)? = nil
    #endif

    private var savedEntry: LibraryEntry? {
        guard !browser.isPrivate, !session.privateMode, session.selectedID == browser.id,
              let failure = browser.loadFailure, let address = failure.targetURL?.absoluteString else { return nil }
        return session.readingList.first { $0.address == address && $0.offlineID != nil }
    }

    var body: some View {
        if let failure = browser.loadFailure {
            Group {
                if fillsPage {
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: failure.symbol)
                                .font(.system(size: 38, weight: .regular)).foregroundStyle(.secondary)
                                .accessibilityHidden(true).padding(.bottom, 4)
                            Text(failure.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                            Text(failure.message).font(.body).foregroundStyle(.secondary)
                            additionalNotice(failure)
                            if let host = failure.targetURL?.host {
                                Text(verbatim: host).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                            actions(failure).padding(.top, 8)
                            Button("Edit Address", action: editAddress).frame(minHeight: 44)
                        }
                        .multilineTextAlignment(.center).frame(maxWidth: 400)
                        .padding(24).frame(maxWidth: .infinity)
                    }
                    .defaultScrollAnchor(.center)
                    .background(Color(uiColor: .systemBackground))
                } else {
                    ViewThatFits(in: .vertical) {
                        inlineFailure(failure).fixedSize(horizontal: false, vertical: true)
                        ScrollView { inlineFailure(failure) }.scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxWidth: 560, maxHeight: max(80, maximumHeight))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 12)
                }
            }
            .accessibilityIdentifier(fillsPage ? "browserFailurePage" : "browserFailureNotice")
            .alert("Couldn’t Open Saved Copy", isPresented: Binding(get: { savedCopyError != nil }, set: { if !$0 { savedCopyError = nil } })) {
                Button("OK", role: .cancel) { savedCopyError = nil }
            } message: { Text(savedCopyError ?? "") }
        } else if let message = browser.errorMessage, !fillsPage {
            ViewThatFits(in: .vertical) {
                localMessage(message).fixedSize(horizontal: false, vertical: true)
                ScrollView { localMessage(message) }.scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: 560, maxHeight: max(80, maximumHeight))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
        }
    }

    private func inlineFailure(_ failure: BrowserLoadFailure) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(failure.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                closeButton
            }
            Text(failure.message).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            additionalNotice(failure)
            actions(failure)
        }.padding(16)
    }

    @ViewBuilder private func additionalNotice(_ failure: BrowserLoadFailure) -> some View {
        if let notice = browser.errorMessage, notice != failure.message {
            Text(notice).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                #if DEBUG
                .background {
                    RecoveryRenderedElementProbe(name: "notice", report: registerElementProbe)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                #endif
        }
    }

    private func localMessage(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            closeButton
        }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
    }

    private var closeButton: some View {
        Button { browser.errorMessage = nil } label: {
            Image(systemName: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
    }

    @ViewBuilder private func actions(_ failure: BrowserLoadFailure) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { recoveryButtons(failure) }
            VStack(spacing: 8) { recoveryButtons(failure) }
        }
        .controlSize(.regular)
    }

    @ViewBuilder private func recoveryButtons(_ failure: BrowserLoadFailure) -> some View {
        if failure.allowsRetry {
            Button(failure.retryLabel) { browser.retryLoadFailure(failure) }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .disabled(browser.isLoading).accessibilityIdentifier("retryPageLoad")
                #if DEBUG
                .background {
                    RecoveryRenderedElementProbe(name: "retry", report: registerElementProbe)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                #endif
        } else if browser.canGoBack {
            Button("Go Back") { browser.goBackFromLoadFailure(failure) }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        if let entry = savedEntry {
            Button("Open Saved Copy") { openSavedCopy(entry, failure: failure) }
                .buttonStyle(.bordered).frame(minHeight: 44)
        }
    }

    private func openSavedCopy(_ entry: LibraryEntry, failure: BrowserLoadFailure) {
        do {
            try session.openSavedCopyForRecovery(entry, browser: browser, failure: failure)
        } catch { savedCopyError = "Try opening the website again." }
    }
}

#if DEBUG
private struct RecoveryRenderedElementProbe: UIViewRepresentable {
    let name: String
    let report: ((String, UIView) -> Void)?
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        // Register the real UIKit probe. The fixture measures its current window/clipping state
        // instead of caching geometry from hidden ViewThatFits measurement candidates.
        report?(name, view)
    }
}
#endif

extension BrowserSession {
    @discardableResult
    func openSavedCopyForRecovery(_ entry: LibraryEntry, browser: BrowserModel, failure: BrowserLoadFailure) throws -> Bool {
        guard let article = try articleForRecovery(entry, browser: browser, failure: failure) else { return false }
        // The copy is a separate presentation. The source document still needs its recovery action.
        browser.readerArticle = article
        return true
    }

    /// Reading a missing/corrupt copy must not replace the navigation failure or its recovery actions.
    func articleForRecovery(_ entry: LibraryEntry, browser: BrowserModel, failure: BrowserLoadFailure) throws -> ReaderArticle? {
        guard browser.loadFailure?.id == failure.id, browser.documentGeneration == failure.documentID,
              !privateMode, !browser.isPrivate, selectedID == browser.id,
              let current = readingList.first(where: { $0.id == entry.id && $0.address == failure.targetURL?.absoluteString }),
              current.offlineID != nil else { return nil }
        // Opening the valid copy is independent of its best-effort read status. A failed status
        // write still rolls back, but must not replace the source page's critical recovery state.
        return try articleForOpening(current, reportReadStatusFailure: false)
    }
}
