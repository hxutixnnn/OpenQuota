import Foundation
import Testing
@testable import OpenUsage

struct AbacusAIUsageMapperTests {
    @Test func mapsEnterpriseMonthlyCredits() throws {
        let json = """
        {
          "type": "system",
          "subtype": "usage_changed",
          "usage": {
            "version": 2,
            "plan": { "tier": "enterprise", "label": "Enterprise" },
            "meters": [
              {
                "id": "rate_limit_spend",
                "label": "Monthly usage limit",
                "scope": "account",
                "unit": "credits",
                "used": 2755.29,
                "limit": 30000,
                "remaining": 27244.71,
                "resets_at": null,
                "period_label": "Resets monthly"
              }
            ]
          }
        }
        """
        let mapped = try AbacusAIUsageMapper.map(Data(json.utf8))
        #expect(mapped.plan == "Enterprise")
        #expect(mapped.lines.count == 1)
        let line = try #require(mapped.lines.first)
        #expect(line.label == "Monthly Credits")
        guard case .progress(_, let used, let limit, let format, _, let periodDurationMs, _) = line else {
            Issue.record("expected a progress line, got \(line)")
            return
        }
        #expect(used == 2755.29)
        #expect(limit == 30000)
        #expect(format == .count(suffix: "credits"))
        #expect(periodDurationMs == AbacusAIUsageMapper.monthlyPeriodMs)
    }

    @Test func monthlyMeterWithoutServerResetCountsToMonthEnd() throws {
        let json = """
        {"usage":{"plan":{"label":"Enterprise"},"meters":[{"id":"rate_limit_spend",
         "label":"Monthly usage limit","unit":"credits","used":3049.88,"limit":30000,
         "resets_at":null,"period_label":"Resets monthly"}]}}
        """
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-21T00:00:00Z"))
        let mapped = try AbacusAIUsageMapper.map(Data(json.utf8), now: now)
        let line = try #require(mapped.lines.first)
        guard case .progress(_, _, _, _, let resetsAt, _, _) = line else {
            Issue.record("expected a progress line")
            return
        }
        let calendar = Calendar.current
        let expected = calendar.date(
            byAdding: .month, value: 1,
            to: try #require(calendar.dateInterval(of: .month, for: now)?.start)
        )
        #expect(resetsAt == expected)
    }

    @Test func serverResetWinsOverMonthEnd() throws {
        let json = """
        {"usage":{"meters":[{"id":"rate_limit_spend","label":"Monthly usage limit","unit":"credits",
         "used":1,"limit":100,"resets_at":"2026-11-25T00:00:00Z","period_label":"Resets monthly"}]}}
        """
        let mapped = try AbacusAIUsageMapper.map(Data(json.utf8))
        let line = try #require(mapped.lines.first)
        guard case .progress(_, _, _, _, let resetsAt, _, _) = line else {
            Issue.record("expected a progress line")
            return
        }
        #expect(resetsAt == ISO8601DateFormatter().date(from: "2026-11-25T00:00:00Z"))
    }

    @Test func throwsOnEmptyMeters() {
        let json = #"{"type":"system","subtype":"usage_changed","usage":{"plan":{"label":"Enterprise"},"meters":[]}}"#
        #expect(throws: AbacusAIError.self) {
            _ = try AbacusAIUsageMapper.map(Data(json.utf8))
        }
    }
}
