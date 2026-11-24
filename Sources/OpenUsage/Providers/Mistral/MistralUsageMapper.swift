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
    /// `resetsAt` comes from `reset_at`; the cycle length varies by calendar month, so no
    /// `periodDurationMs` is invented.
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
            resetsAt: resetsAt
        )
    }
}
