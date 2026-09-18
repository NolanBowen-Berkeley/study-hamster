import Foundation

public enum DurationParser {
    /// Longest accepted study session.
    public static let maximum: TimeInterval = 12 * 3600

    /// Parses what a person types into the hamster's bubble into seconds.
    /// Bare numbers are minutes. Returns nil when unparseable, <= 0 or > `maximum`.
    ///
    /// Accepts (case-insensitive, surrounding whitespace ignored): "90", "90m", "90 min", "45mins",
    /// "1h", "1hr", "2 hours", "1h30", "1h 30m", "1 hour and 30 minutes", "1:30" (h:mm), "1:30:15",
    /// "1.5h", "1,5h", "an hour", "half an hour", "a half hour", "1 and a half hours",
    /// "an hour and a half", "1 1/2 hours", "1½ h", "90s", "90 seconds", "1h 30m 20s".
    /// The result is rounded to whole seconds.
    public static func parse(_ text: String) -> TimeInterval? {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return nil }
        let seconds: TimeInterval?
        if normalized.contains(":") {
            seconds = parseClock(normalized)
        } else if let tokens = tokenize(normalized) {
            var parser = PhraseParser(tokens: tokens)
            seconds = parser.parse()
        } else {
            seconds = nil
        }
        guard let seconds, seconds.isFinite else { return nil }
        let whole = seconds.rounded()
        guard whole > 0, whole <= maximum else { return nil }
        return whole
    }

    // MARK: - Normalization

    /// Lowercases, trims, turns decimal commas into points ("1,5" → "1.5"), other commas into spaces,
    /// "½" into " 1/2", and drops trailing full stops ("90 min.").
    private static func normalize(_ text: String) -> String {
        let characters = Array(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        var result = ""
        for (offset, character) in characters.enumerated() {
            switch character {
            case ",":
                let isDecimal = offset > 0 && offset + 1 < characters.count
                    && characters[offset - 1].isASCIIDigit && characters[offset + 1].isASCIIDigit
                result.append(isDecimal ? "." : " ")
            case "½":
                result.append(" 1/2 ")
            default:
                result.append(character)
            }
        }
        while result.last == "." { result.removeLast() }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - "h:mm" and "h:mm:ss"

    private static func parseClock(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let first = parts.first, !first.isEmpty, first.count <= 3, first.allSatisfy(\.isASCIIDigit),
              let hours = Double(first)
        else { return nil }
        var total = hours * 3600
        for (position, part) in parts.dropFirst().enumerated() {
            guard part.count == 2, part.allSatisfy(\.isASCIIDigit), let value = Double(part), value < 60 else {
                return nil
            }
            total += value * (position == 0 ? 60 : 1)
        }
        return total
    }

    // MARK: - Tokens

    fileprivate enum Unit: Int, Comparable {
        case seconds = 1, minutes = 60, hours = 3600

        var seconds: TimeInterval { TimeInterval(rawValue) }

        /// The unit a bare number after this unit means ("1h30" → 30 minutes).
        var next: Unit? {
            switch self {
            case .hours: return .minutes
            case .minutes: return .seconds
            case .seconds: return nil
            }
        }

        static func < (lhs: Unit, rhs: Unit) -> Bool { lhs.rawValue < rhs.rawValue }

        init?(word: String) {
            switch word {
            case "h", "hr", "hrs", "hour", "hours": self = .hours
            case "m", "min", "mins", "minute", "minutes": self = .minutes
            case "s", "sec", "secs", "second", "seconds": self = .seconds
            default: return nil
            }
        }
    }

    fileprivate enum Token: Equatable {
        case number(Double)
        /// "1/2" written as digits.
        case fraction(Double)
        case word(String)
    }

    /// Splits into numbers, digit fractions and letter words. Returns nil on any other character, so
    /// signs and symbols ("-5", "+5", "$5") are rejected.
    private static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isASCIIDigit || character == "." {
                let end = text[index...].firstIndex { !($0.isASCIIDigit || $0 == ".") } ?? text.endIndex
                guard let value = Double(text[index..<end]) else { return nil }
                index = end
                if index < text.endIndex, text[index] == "/" {
                    let denominatorStart = text.index(after: index)
                    let denominatorEnd = text[denominatorStart...].firstIndex { !$0.isASCIIDigit } ?? text.endIndex
                    guard let denominator = Double(text[denominatorStart..<denominatorEnd]), denominator > 0 else {
                        return nil
                    }
                    tokens.append(.fraction(value / denominator))
                    index = denominatorEnd
                } else {
                    tokens.append(.number(value))
                }
            } else if character.isLetter {
                let end = text[index...].firstIndex { !$0.isLetter } ?? text.endIndex
                tokens.append(.word(String(text[index..<end])))
                index = end
            } else {
                return nil
            }
        }
        return tokens
    }

    // MARK: - Phrases

    /// Recursive-descent parser over the tokens:
    /// ```
    /// input  := term (("and")? term)*
    /// term   := amount unit? ("and" ("a"|"an")? "half")?
    /// amount := number fraction? | fraction | ("a"|"an"|"one") ("half")? | "half" ("a"|"an")?
    ///           followed optionally by "and" ("a"|"an")? "half" for numeric amounts
    /// ```
    /// Units must appear in decreasing order (h, then m, then s), each at most once. A term without a
    /// unit is only allowed last: alone it means minutes; after a unit it means the next smaller unit
    /// ("1h30" = 1 h 30 min) and must then be below 60.
    private struct PhraseParser {
        let tokens: [Token]
        var position = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func parse() -> TimeInterval? {
            var total: TimeInterval = 0
            var lastUnit: Unit?
            var termCount = 0
            while position < tokens.count {
                if termCount > 0, peekWord("and") { position += 1 }
                guard let (amount, needsUnit, hasHalf) = parseAmount() else { return nil }
                termCount += 1

                guard let unit = parseUnit() else {
                    // A unit-less number: must be the final term and not a word amount ("half", "an").
                    guard !needsUnit, position == tokens.count else { return nil }
                    guard let lastUnit else { return amount * Unit.minutes.seconds }
                    guard let implied = lastUnit.next, amount < 60 else { return nil }
                    return total + amount * implied.seconds
                }
                if let lastUnit, unit >= lastUnit { return nil }
                lastUnit = unit

                var value = amount
                if !hasHalf, consumeAndAHalf() { value += 0.5 }
                total += value * unit.seconds
            }
            return termCount > 0 ? total : nil
        }

        /// Returns the amount, whether it came from words (and so requires a unit), and whether it
        /// already includes an "and a half".
        private mutating func parseAmount() -> (value: Double, needsUnit: Bool, hasHalf: Bool)? {
            guard position < tokens.count else { return nil }
            let token = tokens[position]
            position += 1
            switch token {
            case .number(let whole):
                var value = whole
                if position < tokens.count, case .fraction(let fraction) = tokens[position] {
                    value += fraction
                    position += 1
                }
                if consumeAndAHalf() { return (value + 0.5, false, true) }
                return (value, false, false)
            case .fraction(let fraction):
                return (fraction, false, false)
            case .word("a"), .word("an"), .word("one"):
                if peekWord("half") {
                    position += 1
                    return (0.5, true, true)
                }
                return (1, true, false)
            case .word("half"):
                if peekWord("a") || peekWord("an") { position += 1 }
                return (0.5, true, true)
            case .word:
                return nil
            }
        }

        private mutating func parseUnit() -> Unit? {
            guard position < tokens.count, case .word(let word) = tokens[position], let unit = Unit(word: word) else {
                return nil
            }
            position += 1
            return unit
        }

        /// Consumes "and a half", "and an half" or "and half" if it comes next.
        private mutating func consumeAndAHalf() -> Bool {
            guard peekWord("and") else { return false }
            var lookahead = position + 1
            if lookahead < tokens.count, tokens[lookahead] == .word("a") || tokens[lookahead] == .word("an") {
                lookahead += 1
            }
            guard lookahead < tokens.count, tokens[lookahead] == .word("half") else { return false }
            position = lookahead + 1
            return true
        }

        private func peekWord(_ word: String) -> Bool {
            position < tokens.count && tokens[position] == .word(word)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
