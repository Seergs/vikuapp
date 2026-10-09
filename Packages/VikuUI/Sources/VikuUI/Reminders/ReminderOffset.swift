import Foundation
import VikunjaCore

/// A composable relative reminder offset — quantity, unit, and before/after
/// direction — rather than a fixed menu of presets. `ReminderPickerSheet`'s
/// "Relative" mode reads/writes one of these directly; `TaskReminder` itself
/// only stores the flattened `relativePeriod` (seconds), so `seconds`/
/// `decompose(seconds:)` convert between the two shapes.
public struct ReminderOffset: Hashable, Sendable {
    public enum Unit: CaseIterable, Hashable, Sendable {
        case minutes
        case hours
        case days
        case weeks

        public var seconds: Int {
            switch self {
            case .minutes: 60
            case .hours: 3600
            case .days: 86400
            case .weeks: 604_800
            }
        }

        public var localizedLabel: String {
            switch self {
            case .minutes: String(localized: "Minutes", bundle: .module)
            case .hours: String(localized: "Hours", bundle: .module)
            case .days: String(localized: "Days", bundle: .module)
            case .weeks: String(localized: "Weeks", bundle: .module)
            }
        }
    }

    public enum Direction: CaseIterable, Hashable, Sendable {
        case before
        case after

        public var localizedLabel: String {
            switch self {
            case .before: String(localized: "Before", bundle: .module)
            case .after: String(localized: "After", bundle: .module)
            }
        }
    }

    public var quantity: Int
    public var unit: Unit
    public var direction: Direction

    public init(quantity: Int, unit: Unit, direction: Direction) {
        self.quantity = quantity
        self.unit = unit
        self.direction = direction
    }

    /// The flattened offset `TaskReminder.relativePeriod` stores: negative
    /// before the anchor, positive after. `quantity == 0` always yields `0`
    /// regardless of `direction` — "at the anchor" either way.
    public var seconds: Int {
        quantity * unit.seconds * (direction == .before ? -1 : 1)
    }

    /// Reconstructs an offset from a raw `relativePeriod` — snapping to the
    /// largest unit that divides it evenly (weeks, then days, then hours,
    /// then minutes), or rounding to the nearest whole minute on the rare
    /// offset that doesn't divide evenly by any of the four.
    public static func decompose(seconds: Int) -> ReminderOffset {
        let direction: Direction = seconds < 0 ? .before : .after
        let magnitude = abs(seconds)
        guard magnitude > 0 else {
            return ReminderOffset(quantity: 0, unit: .minutes, direction: .before)
        }
        if magnitude.isMultiple(of: Unit.weeks.seconds) {
            return ReminderOffset(quantity: magnitude / Unit.weeks.seconds, unit: .weeks, direction: direction)
        }
        if magnitude.isMultiple(of: Unit.days.seconds) {
            return ReminderOffset(quantity: magnitude / Unit.days.seconds, unit: .days, direction: direction)
        }
        if magnitude.isMultiple(of: Unit.hours.seconds) {
            return ReminderOffset(quantity: magnitude / Unit.hours.seconds, unit: .hours, direction: direction)
        }
        if magnitude.isMultiple(of: Unit.minutes.seconds) {
            return ReminderOffset(quantity: magnitude / Unit.minutes.seconds, unit: .minutes, direction: direction)
        }
        let roundedMinutes = max(1, Int((Double(magnitude) / Double(Unit.minutes.seconds)).rounded()))
        return ReminderOffset(quantity: roundedMinutes, unit: .minutes, direction: direction)
    }

    /// A localized phrase ending in `anchor`'s name: "At due date" when
    /// `quantity` is 0, else e.g. "3 days before due date" / "1 hour after
    /// due date" (pluralized per-locale via the string catalog).
    public func localizedLabel(anchor: ReminderRelation) -> String {
        let anchorName = anchor.localizedDisplayName
        guard quantity > 0 else {
            return String(localized: "At \(anchorName)", bundle: .module)
        }
        return switch (unit, direction) {
        case (.minutes, .before): String(localized: "\(quantity) minutes before \(anchorName)", bundle: .module)
        case (.minutes, .after): String(localized: "\(quantity) minutes after \(anchorName)", bundle: .module)
        case (.hours, .before): String(localized: "\(quantity) hours before \(anchorName)", bundle: .module)
        case (.hours, .after): String(localized: "\(quantity) hours after \(anchorName)", bundle: .module)
        case (.days, .before): String(localized: "\(quantity) days before \(anchorName)", bundle: .module)
        case (.days, .after): String(localized: "\(quantity) days after \(anchorName)", bundle: .module)
        case (.weeks, .before): String(localized: "\(quantity) weeks before \(anchorName)", bundle: .module)
        case (.weeks, .after): String(localized: "\(quantity) weeks after \(anchorName)", bundle: .module)
        }
    }
}

public extension ReminderRelation {
    /// The task date field this relation names, lowercase and mid-sentence
    /// ("due date", not "Due Date") — composed into `ReminderOffset`'s
    /// phrases ("3 days before due date").
    var localizedDisplayName: String {
        switch self {
        case .dueDate: String(localized: "due date", bundle: .module)
        case .startDate: String(localized: "start date", bundle: .module)
        case .endDate: String(localized: "end date", bundle: .module)
        }
    }
}
