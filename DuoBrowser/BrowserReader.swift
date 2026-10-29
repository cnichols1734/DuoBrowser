import SwiftUI
import WebKit

struct ReaderArticle: Identifiable {
    let id = UUID()
    let title: String
    let source: URL
    let blocks: [Block]
    struct Block: Identifiable {
        let id = UUID()
        let heading: Bool
        let text: String
    }
    static func parse(_ value: Any?, source: URL) -> ReaderArticle? {
        guard WebAddress.valid(source) != nil, let object = value as? [String: Any],
              let title = object["title"] as? String, title.count <= 512,
              let entries = object["blocks"] as? [[String: Any]], (2...300).contains(entries.count) else { return nil }
        var blocks: [Block] = []
        var count = 0
        for entry in entries {
            guard let kind = entry["kind"] as? String, ["heading", "paragraph"].contains(kind),
                  let text = entry["text"] as? String, !text.isEmpty, text.count <= 8000 else { return nil }
            count += text.count
            guard count <= 108000 else { return nil }
            blocks.append(Block(heading: kind == "heading", text: text))
        }
        if blocks.first?.heading == true, blocks.first?.text == title { blocks.removeFirst() }
        return ReaderArticle(title: title, source: source, blocks: blocks)
    }
}

extension BrowserModel {
    func cancelReader() {
        readerRequest = UUID()
        readerLoading = false
        readerArticle = nil
    }
    func openReader() {
        guard !readerLoading, !isLoading, let view = loadedWebView, let source = restorationURL,
              let scriptURL = Bundle.main.url(forResource: "Reader", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { return }
        let request = UUID()
        readerRequest = request
        let generation = documentGeneration
        readerLoading = true
        Task { @MainActor [weak self, weak view] in
            guard let view else { return }
            let value = try? await view.evaluateJavaScript(script, in: nil, contentWorld: .world(name: "DuoBrowser.Reader"))
            guard let self, self.readerRequest == request, self.documentGeneration == generation,
                  self.loadedWebView === view, view.url == source else { return }
            self.readerLoading = false
            guard let article = ReaderArticle.parse(value, source: source) else {
                self.errorMessage = "Reader is unavailable for this page. The original page is unchanged."
                return
            }
            self.readerArticle = article
        }
    }
}

struct ReaderView: View {
    let article: ReaderArticle
    @Environment(\.dismiss) private var dismiss
    @State private var size = 19.0
    @State private var spacing = 7.0
    @State private var theme = "System"
    @ScaledMetric(relativeTo: .body) private var scale = 1.0
    private var paper: Color { theme == "Sepia" ? Color(red: 0.96, green: 0.93, blue: 0.85) : Color(uiColor: .systemBackground) }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text(article.source.host ?? "Article").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: article.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                    ForEach(article.blocks) { block in
                        Text(verbatim: block.text)
                            .font(.system(size: (block.heading ? size + 4 : size) * scale,
                                          weight: block.heading ? .semibold : .regular, design: .serif))
                            .lineSpacing(spacing)
                            .accessibilityAddTraits(block.heading ? .isHeader : [])
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 660, alignment: .leading)
                .padding(24).frame(maxWidth: .infinity)
            }
            .background(paper)
            .navigationTitle("Reader").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ControlGroup {
                            Button("Smaller Text", systemImage: "textformat.size.smaller") { size = max(15, size - 2) }
                            Button("Larger Text", systemImage: "textformat.size.larger") { size = min(31, size + 2) }
                        }
                        Picker("Appearance", selection: $theme) {
                            ForEach(["System", "Light", "Sepia", "Dark"], id: \.self) { Text($0) }
                        }
                        Picker("Line Spacing", selection: $spacing) {
                            Text("Compact").tag(3.0); Text("Comfortable").tag(7.0); Text("Relaxed").tag(12.0)
                        }
                    } label: { Label("Reading Settings", systemImage: "textformat.size") }
                }
            }
        }
        .preferredColorScheme(theme == "Dark" ? .dark : theme == "Light" || theme == "Sepia" ? .light : nil)
    }
}
