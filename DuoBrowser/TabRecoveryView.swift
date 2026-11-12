import SwiftUI
import WebKit

struct RecentlyClosedView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if session.recentlyClosed.isEmpty || session.privateMode {
                    ContentUnavailableView("No recently closed tabs", systemImage: "clock.arrow.circlepath",
                        description: Text("The last 20 normal tabs you close appear here. Private tabs are never saved."))
                } else {
                    Section {
                        ForEach(session.recentlyClosed) { record in
                            Button {
                                if session.reopenClosedTab(record.id) { dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: record.title.isEmpty ? record.address : record.title)
                                        .foregroundStyle(.primary).lineLimit(2)
                                    Text(verbatim: URL(string: record.address)?.host ?? record.address)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                    Text(workspaceName(record)).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Reopens the saved address in its workspace")
                            .disabled(session.tabs.count >= 200)
                        }
                    } footer: {
                        Text(session.tabs.count >= 200 ? "Close an open tab before reopening another (200 tab limit)." : "Reopens the saved address and reading position. Page input and navigation history aren't restored.")
                    }
                }
            }
            .navigationTitle("Recently Closed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !session.recentlyClosed.isEmpty && !session.privateMode {
                    ToolbarItem(placement: .bottomBar) { Button("Clear Recently Closed", role: .destructive) { confirmClear = true } }
                }
            }
            .confirmationDialog("Clear recently closed tabs?", isPresented: $confirmClear) {
                Button("Clear Recently Closed", role: .destructive) { session.clearRecentlyClosed() }
            }
        }
    }

    private func workspaceName(_ record: ClosedTabRecord) -> String {
        session.workspaces.first { $0.id == record.workspaceID }?.name
            ?? session.workspaces.first { $0.id == Workspace.defaultID }?.name ?? "Personal"
    }
}

struct ClosedTabNotice: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if !session.privateMode, let id = session.closedTabNotice,
           session.recentlyClosed.contains(where: { $0.id == id }) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { Text("Tab closed"); actions(id) }
                VStack(alignment: .leading, spacing: 4) { Text("Tab closed"); actions(id) }
            }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .task(id: id) {
                // A lasting Recently Closed entry remains after the transient notice is dismissed.
                guard !UIAccessibility.isVoiceOverRunning, !typeSize.isAccessibilitySize else { return }
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, session.closedTabNotice == id else { return }
                session.closedTabNotice = nil
            }
        }
    }

    private func actions(_ id: UUID) -> some View {
        HStack(spacing: 12) {
            Button("Undo") { _ = session.reopenClosedTab(id) }
                .frame(minHeight: 44).disabled(session.tabs.count >= 200)
                .accessibilityHint("Reopens the closed page")
            Button { session.closedTabNotice = nil } label: {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }.accessibilityLabel("Dismiss tab closed notice")
        }
    }
}

struct BackHistoryMenu: ViewModifier {
    @ObservedObject var browser: BrowserModel

    func body(content: Content) -> some View {
        content.contextMenu {
            if let view = browser.loadedWebView {
                ForEach(Array(view.backForwardList.backList.reversed().prefix(30).enumerated()), id: \.offset) { _, item in
                    Button {
                        // The menu can outlive navigation; never act on an item from an obsolete web view/list.
                        guard browser.loadedWebView === view,
                              view.backForwardList.backList.contains(where: { $0 === item }) else { return }
                        view.go(to: item)
                    } label: {
                        Text(verbatim: item.title?.isEmpty == false ? item.title! : item.url.host ?? item.url.absoluteString)
                    }
                }
            }
        }
        .accessibilityHint("Touch and hold for this tab's previous pages")
    }
}
