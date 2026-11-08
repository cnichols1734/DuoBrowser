import SwiftUI

/// A compact command overlay. Its parent keeps it immediately above the keyboard.
struct BrowserSearch: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @Binding var query: String
    let availableHeight: CGFloat
    let dismiss: () -> Void
    // Preserve existing opt-outs while keeping the owner-requested compact UI.
    @AppStorage("onlineSearchSuggestions") private var onlineSuggestions = true
    @State private var composing = false
    @State private var predictions: [String] = []
    @State private var predictionQuery = ""
    @State private var appActive = UIApplication.shared.applicationState == .active
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var metadataSize = 13.0
    @ScaledMetric(relativeTo: .body) private var inputHeight = 52.0
    @ScaledMetric(relativeTo: .body) private var resultHeight = 64.0

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isWebsite: Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.contains(where: \.isWhitespace) && (value.contains(".") || value.contains("://") || value.hasPrefix("localhost"))
    }
    private var results: [SearchResult] {
        AddressSuggestions.results(query, local: session.searchResults(query, isPrivate: browser.isPrivate))
    }

    private var remoteQuery: String? {
        guard appActive else { return nil }
        return AddressSuggestions.remoteQuery(query, isPrivate: browser.isPrivate,
                                               enabled: onlineSuggestions, composing: composing)
    }
    private var visiblePredictions: [String] {
        predictionQuery == remoteQuery ? predictions : []
    }
    private var showsDirectAction: Bool {
        hasQuery && (!typeSize.isAccessibilitySize || availableHeight > inputHeight + resultHeight + 180)
    }
    private var rowCount: Int { results.count + visiblePredictions.count }
    private var resultAreaHeight: CGFloat {
        min(CGFloat(rowCount) * resultHeight,
            max(44, min(availableHeight - inputHeight - (showsDirectAction ? resultHeight : 0) - (typeSize.isAccessibilitySize ? 40 : 100), resultHeight * 4)))
    }

    var body: some View {
        VStack(spacing: 0) {
            if rowCount > 0 {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 0).id("top")
                            if let top = results.first {
                                Button { open(top) } label: { resultRow(top) }.buttonStyle(CommandRowStyle())
                            }
                            ForEach(visiblePredictions, id: \.self) { phrase in
                                HStack(spacing: 0) {
                                    Button { search(phrase) } label: {
                                        searchRow(phrase, detail: "Google suggestion")
                                    }.buttonStyle(CommandRowStyle())
                                    Button { query = phrase } label: {
                                        Image(systemName: "arrow.up.left").frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel("Complete search: " + phrase)
                                    .padding(.trailing, 8)
                                }
                            }
                            ForEach(Array(results.dropFirst())) { result in
                                Button { open(result) } label: { resultRow(result) }.buttonStyle(CommandRowStyle())
                            }
                        }
                    }
                    .frame(height: resultAreaHeight)
                    .scrollIndicators(.hidden)
                    .onChange(of: query) { _, _ in proxy.scrollTo("top", anchor: .top) }
                }
            }
            if showsDirectAction {
                Button { navigate(query) } label: {
                    searchRow(query, detail: isWebsite ? "Open website" : "Search Google")
                }.buttonStyle(CommandRowStyle())
            }
            if rowCount > 0 || hasQuery { Divider().padding(.horizontal, 20) }
            HStack(spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: browser.isPrivate ? "hand.raised" : "magnifyingglass")
                        .font(.body.weight(.medium)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                AddressField(text: $query, submit: { navigate($0) }, cancel: dismiss, cancelOnEndEditing: false, isComposing: $composing)
                    .frame(height: inputHeight)
                    .accessibilityLabel(browser.isPrivate ? "Private website address or search" : "Website address or search")
                Button(action: dismiss) {
                    if typeSize.isAccessibilitySize {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    } else { Text("Cancel").frame(minHeight: 44) }
                }
                .font(.subheadline.weight(.medium)).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Cancel search")
            }
            .padding(.horizontal, 20).padding(.vertical, 4)

        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 8)
        .frame(maxWidth: 600)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            appActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            appActive = true
        }
        .task(id: remoteQuery) {
            predictions = []
            predictionQuery = ""
            guard let request = remoteQuery else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let values = try await SearchSuggestionClient().fetch(request)
                try Task.checkCancellation()
                guard remoteQuery == request else { return }
                predictionQuery = request
                predictions = values
            } catch { /* Offline, cancellation and provider failures leave local results usable. */ }
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: result.kind == .tab ? "square.on.square" : result.kind == .bookmark ? "bookmark" : result.kind == .website ? "globe" : "clock")
                    .font(.body).foregroundStyle(.secondary).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: result.title.isEmpty ? displayAddress(result.address) : result.title)
                    .font(.body.weight(.semibold)).lineLimit(1)
                Text(verbatim: displayAddress(result.address))
                    .font(.system(size: metadataSize)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if result.kind == .tab {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Switch").font(.system(size: metadataSize, weight: .medium))
                    Text(result.detail).font(.system(size: metadataSize)).lineLimit(1)
                }.foregroundStyle(.secondary).frame(maxWidth: 80)
            } else { Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 20).frame(height: resultHeight).contentShape(Rectangle())
    }

    private func searchRow(_ phrase: String, detail: String) -> some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: "magnifyingglass").frame(width: 24).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: phrase).font(.body).lineLimit(1)
                Text(detail).font(.system(size: metadataSize)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 20).frame(maxWidth: .infinity, minHeight: resultHeight)
            .contentShape(Rectangle())
    }
    private func search(_ phrase: String) {
        browser.navigate(to: AddressSuggestions.searchURL(phrase).absoluteString)
        dismiss()
    }
    private func displayAddress(_ address: String) -> String {
        guard let url = URLComponents(string: address), let host = url.host else { return address }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.percentEncodedPath == "/" ? "" : url.percentEncodedPath
        return name + path + (url.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    private func open(_ result: SearchResult) {
        dismiss()
        if let id = result.tabID { session.select(id) }
        else { browser.navigate(to: result.address) }
    }
    private func navigate(_ address: String) { guard !address.isEmpty else { return }; browser.navigate(to: address); dismiss() }
}

private struct CommandRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(.primary.opacity(configuration.isPressed ? 0.06 : 0))
    }
}
