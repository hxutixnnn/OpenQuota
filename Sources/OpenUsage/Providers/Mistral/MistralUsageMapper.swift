import Foundation

/// Builds metric lines from the Mistral `/billing/budget` and `/billing/subscription` payloads.
/// Mistral bills in EUR and reports each monthly allowance as a `usage_percentage` against an
/// `initial_budget`, so the meters are percent meters carrying the provider-reported figure verbatim —
/// the app has no EUR-denominated money format and deriving one would only restate the same ratio.
enum MistralUsageMapper {
    /// `/billing/budget` wraps the API allowance in `api_budget` (also mirrored at the top level) and
    /// the Vibe & Studio allowance in `vibe_budget`.
    static func budgetLines(from data: [String: Any]) -> [MetricLine] {
        var lines: [MetricLine] = []

        let apiBudget = (data["api_budget"] as? [String: Any]) ?? data
        if let line = allowanceLine(apiBudget, label: "API Allowance") {
            lines.append(line)
        }
        if let vibe = data["vibe_budget"] as? [String: Any],
           let line = allowanceLine(vibe, label: "Vibe & Studio Allowance") {
            lines.append(line)
        }

        let payg = ProviderParse.bool(apiBudget["payg_enabled"]) == true
            || ProviderParse.bool((data["vibe_budget"] as? [String: Any])?["payg_enabled"]) == true
        if !lines.isEmpty {
            lines.append(.badge(label: "Pay-as-you-go", text: payg ? "Enabled" : "Disabled"))
        }
        return lines
    }

    /// `/billing/subscription` carries `plan_name` (e.g. "INDIVIDUAL"), title-cased for the card badge.
    static func planName(from data: [String: Any]) -> String? {
        guard let raw = data["plan_name"] as? String, !raw.isEmpty else { return nil }
        return raw.lowercased().capitalized
    }

    /// One percent meter from an allowance object: `usage_percentage` is already a 0…100 figure.
    /// `resetsAt` comes from `reset_at`, and the window behind it is one calendar month, which lets
    /// the row pace instead of falling back to plain level bands.
    private static func allowanceLine(_ budget: [String: Any], label: String) -> MetricLine? {
        guard let pct = ProviderParse.number(budget["usage_percentage"]),
              let budgetAmount = ProviderParse.number(budget["initial_budget"]),
              budgetAmount > 0 else { return nil }
        let resetsAt = (budget["reset_at"] as? String).flatMap(OpenUsageISO8601.date(from:))
        return .progress(
            label: label,
            used: ProviderParse.clampPercent(pct),
            limit: 100,
            format: .percent,
            resetsAt: resetsAt,
            periodDurationMs: resetsAt.flatMap(monthlyPeriodMs(endingAt:))
        )
    }

    /// How long the allowance window that ends at `resetsAt` runs: back to the same day one month
    /// earlier. Without a period the row has a reset date but no window to burn evenly across, so
    /// `WidgetData.meterState` can only report absolute level bands — no pace verdict, tick, or
    /// run-out. Mistral refills on the same day each month, so a fixed 30-day constant would drift up
    /// to a day on 28- and 31-day months and skew the projection. UTC, because `reset_at` is an
    /// instant rather than a local midnight.
    private static func monthlyPeriodMs(endingAt resetsAt: Date) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(byAdding: .month, value: -1, to: resetsAt) else { return nil }
        let milliseconds = Int((resetsAt.timeIntervalSince(start) * 1000).rounded())
        return milliseconds > 0 ? milliseconds : nil
    }
}
