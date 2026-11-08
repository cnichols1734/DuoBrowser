import SwiftUI
import UIKit

/// Native selection avoids appending a new destination to the existing address.
struct AddressField: UIViewRepresentable {
    @Binding var text: String
    var submit: (String) -> Void
    var cancel: () -> Void
    var cancelOnEndEditing = true
    var isComposing: Binding<Bool> = .constant(false)
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = BrowserAddressTextField()
        field.delegate = context.coordinator
        field.onDelete = { context.coordinator.willDelete() }
        field.onEscape = { context.coordinator.parent.cancel() }
        field.placeholder = "Search or enter website"
        field.accessibilityLabel = "Website address or search"
        field.keyboardType = .webSearch
        field.returnKeyType = .go
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.clipsToBounds = true
        field.text = text
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        DispatchQueue.main.async { [weak field] in field?.becomeFirstResponder(); field?.selectAll(nil) }
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(field, text: text)
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressField
        private var completion: (raw: String, display: String, start: Int)?
        private var deleting = false
        private var replacedFromStart = false
        private var updating = false
        init(_ parent: AddressField) { self.parent = parent }
        func willDelete() { deleting = true }

        func synchronize(_ field: UITextField, text: String) {
            guard field.markedTextRange == nil, text != completion?.raw else { return }
            guard field.text != text else { return }
            updating = true
            completion = nil
            field.text = text
            updating = false
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            deleting = string.isEmpty
            replacedFromStart = range.location < 4
            return true
        }

        @objc func changed(_ field: UITextField) {
            guard !updating else { return }
            updating = true
            defer { updating = false; deleting = false; replacedFromStart = false }
            let composing = field.markedTextRange != nil
            parent.isComposing.wrappedValue = composing
            var value = field.text ?? ""
            let prior = completion
            completion = nil
            // The inserted www. is presentation only until the completion is accepted.
            if let prior, !prior.raw.lowercased().hasPrefix("www."), !replacedFromStart,
               value.lowercased().hasPrefix("www.") { value = String(value.dropFirst(4)) }
            // UIKeyInput deletion can omit shouldChangeCharactersIn for a selected suffix.
            deleting = deleting || (prior != nil && value == prior?.raw)
            parent.text = value
            guard !composing else { return }
            let caretAtEnd = field.selectedTextRange.map {
                $0.isEmpty && field.offset(from: field.beginningOfDocument, to: $0.end) == (field.text ?? "").utf16.count
            } ?? false
            if !deleting, caretAtEnd, let suggestion = AddressSuggestions.inlineCompletion(value) {
                completion = (value, suggestion.text, suggestion.selectionStart)
                field.text = suggestion.text
                if let start = field.position(from: field.beginningOfDocument, offset: suggestion.selectionStart) {
                    field.selectedTextRange = field.textRange(from: start, to: field.endOfDocument)
                }
            } else if prior != nil, field.text != value {
                field.text = value
                field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
            }
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            guard !updating, field.markedTextRange == nil, let completion else { return }
            // UIKit may move the selection before delivering the edit that replaces it.
            // Accept a caret move only after that edit has had a chance to finish.
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, !self.updating, field.markedTextRange == nil,
                      self.completion?.raw == completion.raw, field.text == completion.display,
                      let selected = field.selectedTextRange else { return }
                let start = field.offset(from: field.beginningOfDocument, to: selected.start)
                let end = field.offset(from: field.beginningOfDocument, to: selected.end)
                guard start != completion.start || end != completion.display.utf16.count else { return }
                self.completion = nil
                self.parent.text = field.text ?? ""
            }
        }

        func textFieldShouldClear(_ field: UITextField) -> Bool {
            completion = nil
            deleting = true
            return true
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            guard field.markedTextRange == nil else { return false }
            parent.submit(field.text ?? parent.text)
            field.resignFirstResponder()
            return true
        }
        func textFieldDidEndEditing(_ field: UITextField) { if parent.cancelOnEndEditing { parent.cancel() } }
    }
}

private final class BrowserAddressTextField: UITextField {
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    override func deleteBackward() { onDelete?(); super.deleteBackward() }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelEditing))]
    }
    @objc private func cancelEditing() { onEscape?(); resignFirstResponder() }
}
