import SwiftUI

/// Safari-style results canvas with an independently anchored bottom address field.
struct BrowserSearch: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var viewport: BrowserViewportState
    @Binding var query: String
    let dismiss: () -> Void
    @AppStorage("onlineSearchSuggestions") private var onlineSuggestions = true
    @State private var composing = false
    @State private var predictions: [String] = []
    @State private var predictionQuery = ""
    @State private var appActive = UIApplication.shared.applicationState == .active
    @ScaledMetric(relativeTo: .body) private var inputHeight = 48.0

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var results: [SearchResult] { AddressSuggestions.results(query, local: session.searchResults(query, isPrivate: browser.isPrivate)) }
    private var topHit: SearchResult? { hasQuery ? results.first : nil }
    private var completion: String? { composing ? nil : AddressSuggestions.inlineCompletion(query, candidates: results) }
    private var remoteQuery: String? {
        guard appActive else { return nil }
        return AddressSuggestions.remoteQuery(query, isPrivate: browser.isPrivate, enabled: onlineSuggestions, composing: composing)
    }
    private var visiblePredictions: [String] { predictionQuery == remoteQuery ? predictions : [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        if let topHit {
                            Button { open(topHit) } label: { destination(topHit) }
                                .buttonStyle(.plain).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 24))
                                .padding(.bottom, 12)
                        }
                        if hasQuery {
                            HStack {
                                Text(browser.isPrivate || !onlineSuggestions ? "Search" : "Google Suggestions")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                if !browser.isPrivate { suggestionSettings }
                            }.padding(.horizontal, 16).frame(height: 32)
                            Button { search(query) } label: { searchRow(query) }.buttonStyle(.plain)
                            ForEach(visiblePredictions, id: \.self) { phrase in
                                HStack(spacing: 0) {
                                    Button { search(phrase) } label: { searchRow(phrase) }.buttonStyle(.plain)
                                    Button { query = phrase } label: {
                                        Image(systemName: "arrow.down.left.circle").font(.title3).foregroundStyle(.secondary).frame(width: 44, height: 44)
                                    }.buttonStyle(.plain).accessibilityLabel("Complete search: " + phrase).padding(.trailing, 12)
                                }
                            }
                        }
                        let others = topHit == nil ? results : Array(results.dropFirst())
                        if !others.isEmpty {
                            Text("Bookmarks, History and Tabs").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
                            ForEach(others) { result in
                                Button { open(result) } label: { destination(result) }.buttonStyle(.plain)
                            }
                        }
                        if browser.isPrivate {
                            Text("Suggestions stay on this device").font(.caption).foregroundStyle(.secondary).padding(16)
                        }
                    }
                    .padding(.leading, max(12, viewport.nativeInsets.left))
                    .padding(.trailing, max(12, viewport.nativeInsets.right))
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: query) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
            HStack(spacing: 8) {
                AddressField(text: $query, submit: { navigate(query) }, cancel: dismiss, cancelOnEndEditing: false,
                             completion: completion, submitValue: navigate, isComposing: $composing)
                    .accessibilityLabel(browser.isPrivate ? "Private website address or search" : "Website address or search")
                    .frame(height: max(48, inputHeight)).padding(.horizontal, 16)
                    .glassEffect(.regular, in: Capsule())
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.title2).frame(width: max(48, inputHeight), height: max(48, inputHeight))
                }.foregroundStyle(.primary).glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Cancel search")
            }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(.container))
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in appActive = false }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in appActive = true }
        .task(id: remoteQuery) {
            predictions = []; predictionQuery = ""
            guard let request = remoteQuery else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let values = try await SearchSuggestionClient().fetch(request)
                try Task.checkCancellation()
                guard remoteQuery == request else { return }
                predictionQuery = request; predictions = values
            } catch { /* Local results remain usable offline. */ }
        }
    }
    private var suggestionSettings: some View {
        Menu {
            Toggle("Search Engine Suggestions", isOn: $onlineSuggestions)
            Text("When enabled, search text is sent to Google as you type. Website addresses are excluded.")
        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Search suggestion settings")
    }
    private func destination(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.kind == .tab ? "square.on.square" : result.kind == .bookmark ? "bookmark" : result.kind == .history ? "clock" : "globe")
                .font(.title2).frame(width: 30, height: 30)
                .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.kind == .website ? displayAddress(result.address) : result.title).font(.body).lineLimit(1)
                Text(verbatim: displayAddress(result.address)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if result.kind == .tab { Text("Switch").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
    }
    private func searchRow(_ phrase: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary).frame(width: 30, height: 30)
                .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            Group {
                if phrase.lowercased().hasPrefix(query.lowercased()), !query.isEmpty {
                    Text(verbatim: String(phrase.prefix(query.count))) + Text(verbatim: String(phrase.dropFirst(query.count))).foregroundColor(.secondary)
                } else { Text(verbatim: phrase) }
            }.font(.body).lineLimit(2)
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
    }
    private func search(_ phrase: String) { browser.navigate(to: AddressSuggestions.searchURL(phrase).absoluteString); dismiss() }
    private func navigate(_ value: String) { guard !value.isEmpty else { return }; browser.navigate(to: value); dismiss() }
    private func displayAddress(_ address: String) -> String {
        guard let url = URLComponents(string: address), let host = url.host else { return address }
        return host + (url.percentEncodedPath == "/" ? "" : url.percentEncodedPath)
    }
    private func open(_ result: SearchResult) {
        dismiss()
        if let id = result.tabID { session.select(id) } else { browser.navigate(to: result.address) }
    }
}
