import SwiftUI

struct BrowserRecoveryView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    let fillsPage: Bool
    let editAddress: () -> Void
    var maximumHeight: CGFloat = 360
    @State private var savedCopyError: String?

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
            actions(failure)
        }.padding(16)
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
            guard let article = try session.articleForRecovery(entry, browser: browser, failure: failure) else { return }
            browser.errorMessage = nil
            browser.readerArticle = article
        } catch { savedCopyError = "Try opening the website again." }
    }
}

extension BrowserSession {
    /// Reading a missing/corrupt copy must not replace the navigation failure or its recovery actions.
    func articleForRecovery(_ entry: LibraryEntry, browser: BrowserModel, failure: BrowserLoadFailure) throws -> ReaderArticle? {
        guard browser.loadFailure?.id == failure.id, browser.documentGeneration == failure.documentID,
              !privateMode, !browser.isPrivate, selectedID == browser.id,
              let current = readingList.first(where: { $0.id == entry.id && $0.address == failure.targetURL?.absoluteString }),
              current.offlineID != nil else { return nil }
        return try articleForOpening(current)
    }
}
