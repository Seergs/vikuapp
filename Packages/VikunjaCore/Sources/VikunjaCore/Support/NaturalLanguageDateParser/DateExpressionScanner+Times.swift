import Foundation

extension DateExpressionScanner {
    func time(at index: Int, language: Parser.Language) -> Match? {
        var cursor = index
        var introduced = false
        if language == .spanish, sequence(["a", "las"], at: cursor) {
            cursor += 2
            introduced = true
        } else if language == .english, word(cursor) == "at" {
            cursor += 1
            introduced = true
        }
        let named: [String: Int] = language == .spanish ?
            ["mediodía": 12, "mediodia": 12, "medianoche": 0] : ["noon": 12, "midnight": 0]
        if let hour = named[word(cursor)] {
            return Match(
                end: cursor + 1, meaning: .timeOnly, language: language,
                clock: .init(hour: hour, minute: 0), rules: ["R24", "R26"],
            )
        }
        return numericTime(at: cursor, language: language, introduced: introduced)
    }

    private func numericTime(at start: Int, language: Parser.Language, introduced: Bool) -> Match? {
        var cursor = start
        guard let originalHour = Int(word(cursor)) else {
            if !word(cursor).isEmpty, word(cursor).allSatisfy(\.isNumber),
               introduced || word(cursor + 1) == ":" {
                return Match(end: cursor + 1, language: language, outcome: .invalid(.invalidTime), rules: ["R24"])
            }
            if introduced {
                return Match(end: cursor, language: language, outcome: .incomplete, rules: ["R39"])
            }
            return nil
        }
        var hour = originalHour
        cursor += 1
        var minute = 0
        var hasMinutes = false
        if word(cursor) == ":" {
            hasMinutes = true
            cursor += 1
            guard let value = Int(word(cursor)) else {
                return Match(end: cursor, language: language, outcome: .incomplete, rules: ["R39"])
            }
            minute = value
            cursor += 1
            guard word(cursor - 1).count == 2 else {
                return Match(end: cursor, language: language, outcome: .invalid(.invalidTime), rules: ["R24"])
            }
        }
        let hasMeridiem = ["am", "pm"].contains(word(cursor))
        if hasMeridiem {
            guard (1 ... 12).contains(hour) else {
                return Match(end: cursor + 1, language: language, outcome: .invalid(.invalidTime), rules: ["R24"])
            }
            hour = hour % 12 + (word(cursor) == "pm" ? 12 : 0)
            cursor += 1
        }
        guard introduced || hasMinutes || hasMeridiem else { return nil }
        // Consume seconds as an unsupported shape instead of accepting a misleading prefix.
        if word(cursor) == ":", Int(word(cursor + 1)) != nil {
            return Match(end: cursor + 2, language: language, outcome: .invalid(.invalidTime), rules: ["R24"])
        }
        return Match(
            end: cursor, meaning: .timeOnly, language: introduced ? language : nil,
            clock: .init(hour: hour, minute: minute), rules: ["R24", "R26"],
        )
    }
}
