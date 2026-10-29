import Foundation

enum DateText {
    static func display(_ raw: String, withTime: Bool = false) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: raw) }
        guard let date else { return String(raw.prefix(19)) }
        return date.formatted(date: .abbreviated, time: withTime ? .shortened : .omitted)
    }
}
