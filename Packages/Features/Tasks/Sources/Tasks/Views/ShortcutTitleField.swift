#if os(iOS)
import SwiftUI
import UIKit
import VikuDesignSystem
import VikunjaCore

/// The quick-add title field. A `UITextView` rather than a `TextField`, because
/// SwiftUI's text fields cannot color part of their text. Each shortcut is drawn
/// in its tint (see `QuickAddParser.Resolution.tint`) while the text stays in place.
struct ShortcutTitleField: UIViewRepresentable {
    @Binding var text: String
    let tokens: [QuickAddParser.ResolvedToken]
    let focusOnAppear: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.returnKeyType = .done
        view.setContentHuggingPriority(.required, for: .vertical)
        if focusOnAppear {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text {
            // Only set text that came from outside, so typing and marked text
            // (IME composition) are never replaced underneath the user.
            let selection = view.selectedRange
            view.text = text
            let end = view.text.utf16.count
            view.selectedRange = NSRange(location: min(selection.location, end), length: 0)
        }
        applyHighlights(to: view)
    }

    /// Recolors the existing storage in place instead of reassigning the text,
    /// so the caret and any marked text survive the update.
    private func applyHighlights(to view: UITextView) {
        let storage = view.textStorage
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        for item in tokens {
            guard let tint = item.resolution.tint else { continue }
            let range = NSRange(item.token.range, in: view.text)
            storage.addAttributes(
                [
                    .foregroundColor: UIColor(tint),
                    .font: UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold),
                ],
                range: range,
            )
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// The title is one line, so Return dismisses the keyboard instead of inserting a newline.
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String,
        ) -> Bool {
            guard replacement == "\n" else { return true }
            textView.resignFirstResponder()
            return false
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
