import Foundation

/// Small, dependency-free formatters shared across the UI.
enum Format {

    /// `$4.37`, `$12`, `$1.2k` — compact money for tight labels.
    static func money(_ value: Double, compact: Bool = false) -> String {
        if compact && value >= 1000 {
            return "$\(tokens(Int(value)))"
        }
        if value >= 100 {
            return "$\(Int(value.rounded()))"
        }
        return String(format: "$%.2f", value)
    }

    /// `658.6k`, `29.2M`, `12` — human token counts.
    static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch v {
        case 1_000_000...:
            return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", v / 1_000)
        default:
            return "\(value)"
        }
    }

    /// `2d 4h`, `4h 52m`, `48m`, `now` — a coarse countdown from now until `date`.
    /// Days appear once the target is 24h+ away (e.g. the weekly reset).
    static func countdown(to date: Date?) -> String {
        guard let date else { return "—" }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// `9:00 PM` — short local time, used for the block reset stamp.
    static func clockTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// `Updated 14:32` — last refresh stamp for the footer. Once the stamp is no
    /// longer from today the weekday is included: values restored from a previous
    /// session, or an app left running past midnight, would otherwise show a bare
    /// time that reads as "just now".
    static func updatedAt(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "E HH:mm"
        return "Updated \(f.string(from: date))"
    }
}
