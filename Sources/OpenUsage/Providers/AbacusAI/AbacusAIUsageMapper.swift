import Foundation

enum AbacusAIUsageMapper {
    static let monthlyPeriodMs = 30 * 24 * 60 * 60 * 1_000

    static func map(_ body: Data, now: Date = Date()) throws -> (plan: String?, lines: [MetricLine]) {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            throw AbacusAIError.invalidResponse
        }

        let plan = (usage["plan"] as? [String: Any])?["label"] as? String
        let meters = usage["meters"] as? [[String: Any]] ?? []
        var lines: [MetricLine] = []

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        for meter in meters {
            guard let used = number(meter["used"]),
                  let limit = number(meter["limit"]),
                  limit > 0 else { continue }
            let id = meter["id"] as? String ?? ""
            let label = id == "rate_limit_spend"
                ? "Monthly Credits"
                : (meter["label"] as? String ?? "Credits")
            let unit = meter["unit"] as? String ?? "credits"
            let periodLabel = (meter["period_label"] as? String ?? "").lowercased()
            let periodMs = periodLabel.contains("month") ? monthlyPeriodMs : nil
            // Abacus sends no `resets_at` for enterprise orgs. The meter is a calendar-month allowance,
            // so count down to the first of next month (local time) instead of showing no reset at all.
            let resetsAt: Date? = (meter["resets_at"] as? String).flatMap {
                iso.date(from: $0) ?? isoPlain.date(from: $0)
            } ?? (periodMs == nil ? nil : endOfMonth(now))
            let roundedUsed = (used * 100).rounded() / 100
            lines.append(.progress(
                label: label,
                used: roundedUsed,
                limit: limit,
                format: .count(suffix: unit),
                resetsAt: resetsAt,
                periodDurationMs: periodMs
            ))
        }

        guard !lines.isEmpty else { throw AbacusAIError.noMeters }
        return (plan, lines)
    }

    /// Local midnight on the first of the month after `date` — when a calendar-month meter refills.
    static func endOfMonth(_ date: Date, calendar: Calendar = .current) -> Date? {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: monthStart)
    }

    private static func number(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }
}
