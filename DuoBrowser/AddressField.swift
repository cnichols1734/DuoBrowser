import SwiftUI
import UIKit

/// Native selection avoids appending a new destination to the existing address.
struct AddressField: UIViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var cancel: () -> Void
    var cancelOnEndEditing = true
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
        if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressField
        init(_ parent: AddressField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { parent.submit(); field.resignFirstResponder(); return true }
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
