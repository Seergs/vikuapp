#if os(iOS)
import SwiftUI
import UIKit
import VikuDesignSystem
import VikunjaCore

/// The quick-add title field. A `UITextView` rather than a `TextField`, because
/// SwiftUI's text fields cannot color part of their text. Each shortcut is drawn
/// in its tint alongside recognized dates, while the text stays in place.
struct ShortcutTitleField: UIViewRepresentable {
    @Binding var text: String
    let highlights: QuickAddTitleHighlights
    let focusOnAppear: Bool
    var textStyle: UIFont.TextStyle = .body

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
        // Set directly here, with the caret at the end, rather than left to
        // `updateUIView`'s own `view.text != text` diff on the first call:
        // that diff's `min(selection.location, end)` assumes `selection`
        // reflects a real prior cursor spot, which is only true once the
        // user has actually interacted with the field. For a prefilled
        // title (e.g. from the "create as new task" relation picker) a
        // fresh `UITextView`'s default `selectedRange` is `{0, 0}`, so that
        // diff would otherwise land the caret at the very start of text the
        // user never typed.
        view.text = text
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        if focusOnAppear {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = context.environment.isEnabled
        context.coordinator.text = $text
        context.coordinator.refreshHighlights = { view in
            guard view.markedTextRange == nil else { return }
            applyHighlights(to: view)
        }
        // Leave an in-progress IME composition untouched until UIKit commits it.
        guard view.markedTextRange == nil else { return }
        if view.text != text {
            // Only set text that came from outside, so typing and marked text
            // (IME composition) are never replaced underneath the user.
            let selection = view.selectedRange
            view.text = text
            let end = view.text.utf16.count
            let location = min(selection.location, end)
            view.selectedRange = NSRange(location: location, length: min(selection.length, end - location))
        }
        applyHighlights(to: view)
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let fitting = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        view.isScrollEnabled = fitting.height > maxContentHeight
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
        return CGSize(width: width, height: min(fitting.height, maxContentHeight))
    }

    private var maxContentHeight: CGFloat {
        ceil(UIFont.preferredFont(forTextStyle: textStyle).lineHeight * Self.maxVisibleLines)
    }

    /// Recolors the existing storage in place instead of reassigning the text,
    /// so the caret and any marked text survive the update.
    private func applyHighlights(to view: UITextView) {
        guard view.text == highlights.input else { return }
        let selection = view.selectedRange
        let storage = view.textStorage
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: textStyle),
            .foregroundColor: UIColor(palette.textPrimary),
        ]
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        for span in highlights.spans {
            guard let tint = span.style.tint(in: palette) else { continue }
            let range = NSRange(span.range, in: highlights.input)
            storage.addAttributes(
                [
                    .foregroundColor: UIColor(tint),
                    .font: UIFont.preferredFont(forTextStyle: textStyle).withWeight(.semibold),
                ],
                range: range,
            )
        }
        storage.endEditing()
        view.selectedRange = selection
        // New ordinary text must not inherit the color of the preceding shortcut/date.
        view.typingAttributes = base
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var refreshHighlights: ((UITextView) -> Void)?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            // IME commits can leave the string unchanged; refresh using the latest snapshot.
            refreshHighlights?(textView)
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
