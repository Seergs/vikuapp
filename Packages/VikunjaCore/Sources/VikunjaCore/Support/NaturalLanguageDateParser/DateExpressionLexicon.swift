import Foundation

/// Explicit vocabulary: no locale-dependent matching or general typo correction.
struct DateExpressionLexicon {
    typealias Language = NaturalLanguageDateParser.Language
    typealias Unit = NaturalLanguageDateParser.Unit

    let language: Language

    var weekdays: [String] {
        switch language {
        case .spanish: ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"]
        case .english: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        }
    }

    var months: [String] {
        switch language {
        case .spanish:
            [
                "enero",
                "febrero",
                "marzo",
                "abril",
                "mayo",
                "junio",
                "julio",
                "agosto",
                "septiembre",
                "octubre",
                "noviembre",
                "diciembre",
            ]
        case .english:
            [
                "january",
                "february",
                "march",
                "april",
                "may",
                "june",
                "july",
                "august",
                "september",
                "october",
                "november",
                "december",
            ]
        }
    }

    func weekday(_ word: String) -> Int? {
        let aliases = ["sabado": "sábado", "miercoles": "miércoles"]
        let value = language == .spanish ? aliases[word] ?? word : word
        return weekdays.firstIndex(of: value).map { $0 + 1 }
    }

    func month(_ word: String) -> Int? {
        months.firstIndex(of: word).map { $0 + 1 }
    }

    func unit(_ word: String) -> Unit? {
        switch language {
        case .spanish:
            switch word {
            case "día", "días", "dia", "dias": .day
            case "semana", "semanas": .week
            case "mes", "meses": .month
            case "año", "años": .year
            default: nil
            }
        case .english:
            switch word {
            case "day", "days": .day
            case "week", "weeks": .week
            case "month", "months": .month
            case "year", "years": .year
            default: nil
            }
        }
    }

    func number(_ words: [String]) -> Int? {
        if words.count == 1 {
            let word = words[0]
            if word.allSatisfy(\.isASCII), word.allSatisfy(\.isNumber) {
                return Int(word)
            }
            if (language == .spanish && ["un", "una"].contains(word)) ||
                (language == .english && ["a", "an"].contains(word)) {
                return 1
            }
            if let index = numberWords.firstIndex(of: word) {
                return index + 1
            }
            if language == .english, word == "thirty" {
                return 30
            }
            let aliases = [
                "dieciseis": 16, "veintiún": 21, "veintiun": 21, "veintiuna": 21,
                "veintidos": 22, "veintitres": 23, "veintiseis": 26,
            ]
            if language == .spanish {
                return aliases[word]
            }
        }
        if language == .english, words.count == 2 || words.count == 3,
           words[0] == "twenty" {
            if words.count == 3, words[1] != "-" {
                return nil
            }
            let suffix = words.count == 3 && words[1] == "-" ? words[2] : words[1]
            if let index = numberWords.prefix(9).firstIndex(of: suffix) {
                return 21 + index
            }
        }
        return nil
    }

    private var numberWords: [String] {
        switch language {
        case .spanish:
            [
                "uno",
                "dos",
                "tres",
                "cuatro",
                "cinco",
                "seis",
                "siete",
                "ocho",
                "nueve",
                "diez",
                "once",
                "doce",
                "trece",
                "catorce",
                "quince",
                "dieciséis",
                "diecisiete",
                "dieciocho",
                "diecinueve",
                "veinte",
                "veintiuno",
                "veintidós",
                "veintitrés",
                "veinticuatro",
                "veinticinco",
                "veintiséis",
                "veintisiete",
                "veintiocho",
                "veintinueve",
                "treinta",
            ]
        case .english:
            [
                "one",
                "two",
                "three",
                "four",
                "five",
                "six",
                "seven",
                "eight",
                "nine",
                "ten",
                "eleven",
                "twelve",
                "thirteen",
                "fourteen",
                "fifteen",
                "sixteen",
                "seventeen",
                "eighteen",
                "nineteen",
                "twenty",
            ]
        }
    }
}
