import Foundation

/// Offline, deterministic temporal interpretation. Source text is never edited.
/// Account-zone selection and accepted/dismissed occurrence tracking belong to callers.
public enum NaturalLanguageDateParser {
    public enum Language: String, CaseIterable, Sendable {
        case spanish
        case english
    }

    public struct Context: Sendable {
        public let referenceDate: Date
        public let timeZone: TimeZone
        public let languages: Set<Language>

        public init(referenceDate: Date, timeZone: TimeZone, languages: Set<Language>) {
            self.referenceDate = referenceDate
            self.timeZone = timeZone
            self.languages = languages
        }
    }

    public enum Unit: String, Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    public enum WeekdaySelection: Equatable, Sendable {
        case includingToday
        case strictlyFuture
        case currentWeek
    }

    public enum Meaning: Equatable, Sendable {
        case relative(amount: Int, unit: Unit)
        /// Gregorian weekday numbering: Sunday = 1, Saturday = 7.
        case weekday(Int, selection: WeekdaySelection)
        case calendarDate(year: Int?, month: Int, day: Int)
        case timeOnly
    }

    public enum Precision: Equatable, Sendable {
        case day
        case minute
    }

    public struct ResolvedDate: Equatable, Sendable {
        public let date: Date
        public let components: DateComponents
        public let timeZoneIdentifier: String
        public let hasExplicitTime: Bool

        public var precision: Precision {
            hasExplicitTime ? .minute : .day
        }
    }

    /// Machine-readable diagnostics; localization is a consumer responsibility.
    public enum Issue: Equatable, Sendable {
        case invalidDate
        case invalidTime
        case outOfRange
        case pastDayInCurrentWeek
        case repeatedLocalTime
        case nonexistentLocalTime(suggestion: Date?)
        case recurrence
        case vagueExpression
        case compoundOffset
        case unsupportedQuantity
        case writtenTimeZone
        case numericDateFormat
        case mixedLanguage
        case nonAssertiveExpression
        case dateRange
        case conflictingLanguages
    }

    public enum Outcome: Equatable, Sendable {
        case resolved(ResolvedDate)
        case ambiguous(Issue, alternatives: [ResolvedDate])
        case invalid(Issue)
        case incomplete
        case unsupported(Issue)
    }

    public struct Expression: Equatable, Sendable {
        /// Valid only for the exact original input. Not a durable editing identity.
        public let range: Range<String.Index>
        public let text: String
        /// ISO calendar dates have no recognition language.
        public let language: Language?
        public let meaning: Meaning?
        public let ruleIDs: [String]
        public let outcome: Outcome
    }

    public enum Status: Equatable, Sendable {
        case noMatch
        case resolved
        case ambiguous
        case invalid
        case incomplete
        case unsupported
    }

    public struct Result: Equatable, Sendable {
        public let expressions: [Expression]

        /// Multiple expressions have no automatic winner, even if one is resolved.
        public var status: Status {
            guard let first = expressions.first else { return .noMatch }
            guard expressions.count == 1 else { return .ambiguous }
            switch first.outcome {
            case .resolved: return .resolved
            case .ambiguous: return .ambiguous
            case .invalid: return .invalid
            case .incomplete: return .incomplete
            case .unsupported: return .unsupported
            }
        }

        public var resolvedDate: ResolvedDate? {
            guard expressions.count == 1, case let .resolved(value) = expressions[0].outcome else { return nil }
            return value
        }
    }

    public static func parse(
        _ input: String,
        context: Context,
        protecting protectedRanges: [Range<String.Index>] = [],
    ) -> Result {
        DateExpressionScanner(input: input, context: context, protectedRanges: protectedRanges).parse()
    }
}
