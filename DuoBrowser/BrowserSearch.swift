import SwiftUI

/// A compact command overlay. Its parent keeps it immediately above the keyboard.
struct BrowserSearch: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @Binding var query: String
    let availableHeight: CGFloat
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var metadataSize = 13.0
    @ScaledMetric(relativeTo: .body) private var inputHeight = 52.0
    @ScaledMetric(relativeTo: .body) private var resultHeight = 64.0

    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var isWebsite: Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.contains(where: \.isWhitespace) && (value.contains(".") || value.contains("://") || value.hasPrefix("localhost"))
    }
    private var visibleCount: Int {
        max(1, min(availableHeight > 650 ? 4 : 3, Int((availableHeight * 0.72 - inputHeight - 16) / resultHeight)))
    }
    private var results: [SearchResult] {
        var libraryURLs = Set<String>()
        return session.searchResults(query, isPrivate: browser.isPrivate).filter { result in
            if result.kind == .tab { return true }
            var url = URLComponents(string: result.address)
            url?.fragment = nil
            return libraryURLs.insert(url?.string ?? result.address).inserted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button { open(result) } label: { resultRow(result) }
                                .buttonStyle(CommandRowStyle())
                        }
                    }
                }
                .frame(height: CGFloat(min(results.count, visibleCount)) * resultHeight)
                .scrollIndicators(.hidden)
            }
            if results.isEmpty && hasQuery {
                Button(action: navigate) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.body).frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(query).font(.body.weight(.semibold)).lineLimit(1)
                            Text(isWebsite ? "Open website" : "Search the web").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "return").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).frame(height: resultHeight).contentShape(Rectangle())
                }.buttonStyle(CommandRowStyle())
            }
            if !results.isEmpty || hasQuery { Divider().padding(.horizontal, 20) }
            HStack(spacing: 12) {
                Image(systemName: browser.isPrivate ? "hand.raised" : "magnifyingglass")
                    .font(.body.weight(.medium)).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                AddressField(text: $query, submit: navigate, cancel: dismiss, cancelOnEndEditing: false)
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
    }

    private func resultRow(_ result: SearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: result.kind == .tab ? "square.on.square" : result.kind == .bookmark ? "bookmark" : "clock")
                .font(.body).foregroundStyle(.secondary).frame(width: 24)
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
    private func navigate() { guard hasQuery else { return }; browser.navigate(to: query); dismiss() }
}

private struct CommandRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(.primary.opacity(configuration.isPressed ? 0.06 : 0))
    }
}
