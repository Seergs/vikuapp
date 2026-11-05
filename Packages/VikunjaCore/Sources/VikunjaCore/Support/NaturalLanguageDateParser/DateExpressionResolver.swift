import Foundation

struct DateExpressionResolver {
    typealias Parser = NaturalLanguageDateParser

    struct Clock {
        let hour: Int
        let minute: Int
    }

    let context: Parser.Context

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = context.timeZone
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    func resolve(_ meaning: Parser.Meaning, clock: Clock?) -> Parser.Outcome {
        guard isSupported(context.referenceDate) else { return .invalid(.outOfRange) }
        let today = calendar.startOfDay(for: context.referenceDate)
        switch meaning {
        case let .relative(amount, unit):
            guard let day = relativeDay(amount: amount, unit: unit, today: today) else {
                return .invalid(.outOfRange)
            }
            return resolveTime(on: day, clock: clock)
        case let .calendarDate(year, month, day):
            return resolveCalendarDate(year: year, month: month, day: day, today: today, clock: clock)
        case let .weekday(weekday, selection):
            let current = calendar.component(.weekday, from: today)
            var offset = (weekday - current + 7) % 7
            if selection == .strictlyFuture, offset == 0 {
                offset = 7
            }
            if selection == .currentWeek {
                offset = (weekday + 5) % 7 - (current + 5) % 7
            }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else {
                return .invalid(.outOfRange)
            }
            if offset < 0 {
                let following = calendar.date(byAdding: .day, value: 7, to: day)
                let alternatives = [day, following].compactMap(\.self).flatMap { resolvedValues(on: $0, clock: clock) }
                return .ambiguous(.pastDayInCurrentWeek, alternatives: alternatives)
            }
            return resolveTime(on: day, clock: clock)
        case .timeOnly:
            let outcome = resolveTime(on: today, clock: clock)
            // Equality is upcoming: a time exactly equal to the reference is due now.
            let values = resolvedValues(on: today, clock: clock)
            if !values.isEmpty, values.allSatisfy({ $0.date < context.referenceDate }),
               let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                return resolveTime(on: tomorrow, clock: clock)
            }
            return outcome
        }
    }

    private func relativeDay(amount: Int, unit: Parser.Unit, today: Date) -> Date? {
        guard amount >= 0 else { return nil }
        let components = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        switch unit {
        case .day, .week:
            // Absolute safety bound exceeds the entire supported Gregorian interval.
            guard amount <= (unit == .week ? 521_775 : 3_652_425) else { return nil }
            return calendar.date(byAdding: .day, value: amount * (unit == .week ? 7 : 1), to: today)
        case .month, .year:
            guard amount <= (unit == .year ? 9997 : 119_975) else { return nil }
            let target = (year * 12 + month - 1) + amount * (unit == .year ? 12 : 1)
            let targetYear = target / 12
            let targetMonth = target % 12 + 1
            guard (2 ... 9999).contains(targetYear),
                  let first = strictDay(year: targetYear, month: targetMonth, day: 1),
                  let days = calendar.range(of: .day, in: .month, for: first) else { return nil }
            return strictDay(year: targetYear, month: targetMonth, day: min(day, days.count))
        }
    }

    private func resolveCalendarDate(
        year: Int?, month: Int, day: Int, today: Date, clock: Clock?,
    ) -> Parser.Outcome {
        guard (1 ... 12).contains(month), (1 ... 31).contains(day) else { return .invalid(.invalidDate) }
        if let year {
            guard (2 ... 9999).contains(year) else { return .invalid(.outOfRange) }
            guard let date = strictDay(year: year, month: month, day: day) else { return .invalid(.invalidDate) }
            return resolveTime(on: date, clock: clock)
        }
        let currentYear = calendar.component(.year, from: today)
        // Eight years also covers the leap-year gap around a non-leap century.
        for candidateYear in currentYear ... min(currentYear + 8, 9999) {
            if let date = strictDay(year: candidateYear, month: month, day: day), date >= today {
                return resolveTime(on: date, clock: clock)
            }
        }
        if strictDay(year: 2000, month: month, day: day) == nil {
            return .invalid(.invalidDate)
        }
        return .invalid(.outOfRange)
    }

    private func strictDay(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private func resolveTime(on day: Date, clock: Clock?) -> Parser.Outcome {
        guard calendar.component(.era, from: day) == 1,
              (2 ... 9999).contains(calendar.component(.year, from: day)) else { return .invalid(.outOfRange) }
        let hour = clock?.hour ?? 23
        let minute = clock?.minute ?? 59
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return .invalid(.invalidTime) }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = clock == nil ? 59 : 0
        let before = calendar.startOfDay(for: day).addingTimeInterval(-1)
        let first = calendar.nextDate(
            after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first,
        )
        let last = calendar.nextDate(
            after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last,
        )
        guard let first, calendar.isDate(first, inSameDayAs: day) else {
            let suggestion = calendar.nextDate(after: before, matching: components, matchingPolicy: .nextTime)
            return .invalid(.nonexistentLocalTime(suggestion: suggestion))
        }
        guard isSupported(first) else { return .invalid(.outOfRange) }
        let initial = resolved(first, explicit: clock != nil)
        if let last, last != first, calendar.isDate(last, inSameDayAs: day), isSupported(last) {
            return .ambiguous(.repeatedLocalTime, alternatives: [initial, resolved(last, explicit: clock != nil)])
        }
        return .resolved(initial)
    }

    private func resolvedValues(on day: Date, clock: Clock?) -> [Parser.ResolvedDate] {
        switch resolveTime(on: day, clock: clock) {
        case let .resolved(value): [value]
        case let .ambiguous(_, alternatives): alternatives
        default: []
        }
    }

    private func resolved(_ date: Date, explicit: Bool) -> Parser.ResolvedDate {
        Parser.ResolvedDate(
            date: date,
            components: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
            timeZoneIdentifier: context.timeZone.identifier,
            hasExplicitTime: explicit,
        )
    }

    private func isSupported(_ date: Date) -> Bool {
        // Reject pathological finite inputs before asking Foundation to decompose them.
        // This coarse guard is wider than the full four-digit-year interval.
        guard date.timeIntervalSinceReferenceDate.isFinite,
              abs(date.timeIntervalSince1970) < 400_000_000_000 else { return false }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? context.timeZone
        // Four-digit ISO years; year 1 is reserved for Vikunja's no-date sentinel.
        return calendar.component(.era, from: date) == 1 && utc.component(.era, from: date) == 1 &&
            (2 ... 9999).contains(calendar.component(.year, from: date)) &&
            (2 ... 9999).contains(utc.component(.year, from: date))
    }
}
