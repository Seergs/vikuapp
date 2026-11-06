import VikunjaCore

/// Presentation ranges are valid only for this exact input snapshot.
struct QuickAddTitleHighlights: Equatable {
    enum Style: Equatable {
        case shortcut(QuickAddParser.Resolution)
        case date
    }

    struct Span: Equatable {
        let range: Range<String.Index>
        let style: Style
    }

    let input: String
    let spans: [Span]
}
