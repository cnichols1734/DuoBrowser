import SwiftUI
import UIKit

/// Native selection avoids appending a new destination to the existing address.
struct AddressField: UIViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var cancel: () -> Void
    var cancelOnEndEditing = true
    var completion: String? = nil
    var submitValue: ((String) -> Void)? = nil
    var isComposing: Binding<Bool> = .constant(false)
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = BrowserAddressTextField()
        field.delegate = context.coordinator
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
        context.coordinator.refresh(field)
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressField
        var appliedCompletion: String?
        var allowsCompletion = true
        var applying = false
        func refresh(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            if let completed = appliedCompletion, let selection = field.selectedTextRange,
               field.offset(from: field.beginningOfDocument, to: selection.start) != parent.text.utf16.count ||
                field.offset(from: field.beginningOfDocument, to: selection.end) != completed.utf16.count {
                // A user moved the caret or changed the selection; leave native editing alone.
                allowsCompletion = false; appliedCompletion = nil
                return
            }
            applying = true
            defer { applying = false }
            let typed = parent.text
            if allowsCompletion, let completion = parent.completion, completion.hasPrefix(typed), completion != typed,
               let start = field.position(from: field.beginningOfDocument, offset: typed.utf16.count) {
                field.text = completion
                // Recreate positions after replacing text, retaining the typed prefix unselected.
                let prefix = field.position(from: field.beginningOfDocument, offset: typed.utf16.count) ?? start
                field.selectedTextRange = field.textRange(from: prefix, to: field.endOfDocument)
                appliedCompletion = completion
            } else {
                if field.text != typed { field.text = typed }
                appliedCompletion = nil
            }
        }
        init(_ parent: AddressField) { self.parent = parent }
        @objc func changed(_ field: UITextField) {
            appliedCompletion = nil
            parent.isComposing.wrappedValue = field.markedTextRange != nil
            parent.text = field.text ?? ""
        }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Let UIKit own marked-text composition. Ordinary edits are applied atomically so a
            // selection callback cannot accidentally turn the displayed suffix into typed input.
            guard parent.completion != nil || appliedCompletion != nil else { allowsCompletion = !string.isEmpty; return true }
            guard field.markedTextRange == nil else { return true }
            allowsCompletion = !string.isEmpty
            applying = true
            defer { applying = false }
            if string.isEmpty, let completed = appliedCompletion,
               range.location == parent.text.utf16.count, range.length == completed.utf16.count - parent.text.utf16.count {
                field.text = parent.text
                appliedCompletion = nil
                return false
            }
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let value = current.replacingCharacters(in: swiftRange, with: string)
            appliedCompletion = nil
            field.text = value
            if let cursor = field.position(from: field.beginningOfDocument, offset: range.location + string.utf16.count) {
                field.selectedTextRange = field.textRange(from: cursor, to: cursor)
            }
            parent.text = value
            return false
        }
        func textFieldShouldClear(_ field: UITextField) -> Bool {
            appliedCompletion = nil; allowsCompletion = false
            return true
        }
        func textFieldDidChangeSelection(_ field: UITextField) {
            guard !applying, let completed = appliedCompletion, let selection = field.selectedTextRange else { return }
            let start = field.offset(from: field.beginningOfDocument, to: selection.start)
            let end = field.offset(from: field.beginningOfDocument, to: selection.end)
            if start != parent.text.utf16.count || end != completed.utf16.count {
                appliedCompletion = nil; allowsCompletion = false; parent.text = field.text ?? ""
            }
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            if let submitValue = parent.submitValue { submitValue(field.text ?? parent.text) } else { parent.submit() }
            field.resignFirstResponder(); return true
        }
        func textFieldDidEndEditing(_ field: UITextField) { if parent.cancelOnEndEditing { parent.cancel() } }
    }
}

private final class BrowserAddressTextField: UITextField {
    var onEscape: (() -> Void)?
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelEditing))]
    }
    @objc private func cancelEditing() { onEscape?(); resignFirstResponder() }
}
