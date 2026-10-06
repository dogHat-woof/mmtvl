import Foundation

/// XMLTV timestamps: `YYYYMMDDhhmmss` (or a leading part, at least to the minute), optionally followed by `±hhmm`.
nonisolated enum XMLTVDate {
    /// "20261005143000 +0000", "20261005143000", "202610051430 -0500", "20261005143000+0100".
    /// Needs at least YYYYMMDDhhmm; missing seconds = 0; missing offset = UTC. nil when malformed.
    static func parse(_ string: String) -> Date? {
        let scalars = Array(string.trimmingCharacters(in: .whitespaces).unicodeScalars)
        var index = 0
        var digits: [Int] = []
        while index < scalars.count, let digit = digitValue(scalars[index]) {
            digits.append(digit)
            index += 1
        }
        guard digits.count == 12 || digits.count == 14 else { return nil }
        func number(_ range: Range<Int>) -> Int { digits[range].reduce(0) { $0 * 10 + $1 } }

        var offsetSeconds = 0
        while index < scalars.count, scalars[index] == " " { index += 1 }
        if index < scalars.count {
            let sign: Int
            switch scalars[index] {
            case "+": sign = 1
            case "-": sign = -1
            default: return nil
            }
            let offsetDigits = scalars[(index + 1)...].compactMap(digitValue)
            guard offsetDigits.count == 4, scalars.count - index - 1 == 4 else { return nil }
            let hours = offsetDigits[0] * 10 + offsetDigits[1]
            let minutes = offsetDigits[2] * 10 + offsetDigits[3]
            offsetSeconds = sign * (hours * 3600 + minutes * 60)
        }

        var components = DateComponents()
        components.year = number(0..<4)
        components.month = number(4..<6)
        components.day = number(6..<8)
        components.hour = number(8..<10)
        components.minute = number(10..<12)
        components.second = digits.count == 14 ? number(12..<14) : 0
        guard let month = components.month, (1...12).contains(month),
              let day = components.day, (1...31).contains(day),
              let hour = components.hour, hour < 24,
              let minute = components.minute, minute < 60,
              let second = components.second, second < 61,
              let utc = calendar.date(from: components)
        else { return nil }
        return utc.addingTimeInterval(TimeInterval(-offsetSeconds))
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func digitValue(_ scalar: Unicode.Scalar) -> Int? {
        ("0"..."9").contains(scalar) ? Int(scalar.value) - 48 : nil
    }
}
