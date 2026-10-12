#if os(iOS)
import SwiftUI
import UIKit
import VikuDesignSystem
import VikunjaCore

/// The quick-add title field. A `UITextView` rather than a `TextField`, because
/// SwiftUI's text fields cannot color part of their text. Each shortcut is drawn
/// in its tint (see `QuickAddParser.Resolution.tint(in:)`) while the text stays in place.
struct ShortcutTitleField: UIViewRepresentable {
    @Binding var text: String
    let tokens: [QuickAddParser.ResolvedToken]
    let focusOnAppear: Bool

    @Environment(\.vikuPalette) private var palette

    /// Caps the field at this many lines before it scrolls internally, so a
    /// long title wraps onto a few lines (like Todoist's quick-add) instead
    /// of growing forever and pushing the rest of the sheet off-screen.
    static let maxVisibleLines: CGFloat = 3

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
        // Shortcuts like #"Project name" depend on literal straight quotes; autocorrect's
        // smart punctuation would silently swap them for curly quotes the parser can't match.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
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
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        view.isScrollEnabled = fitting.height > Self.maxContentHeight
    }

    /// Reports the field's own natural size back to SwiftUI, capped at
    /// `maxVisibleLines`, instead of the uncapped `intrinsicContentSize` a
    /// scroll-disabled `UITextView` would otherwise report. Past the cap,
    /// `updateUIView` turns scrolling back on so further typing scrolls
    /// inside the field rather than growing it.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (uiView.bounds.width > 0 ? uiView.bounds.width : nil) else {
            return nil
        }
        let fitting = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(fitting.height, Self.maxContentHeight))
    }

    private static var maxContentHeight: CGFloat {
        ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight * maxVisibleLines)
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
            guard let tint = item.resolution.tint(in: palette) else { continue }
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
