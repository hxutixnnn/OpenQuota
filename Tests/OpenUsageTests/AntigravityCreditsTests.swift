import Foundation
import Testing
@testable import OpenUsage

struct AntigravityCreditsTests {
    @Test func creditsFromUserStatus() throws {
        let json = """
        {
          "userStatus": {
            "planStatus": {
              "planInfo": {
                "planName": "Pro",
                "monthlyPromptCredits": 50000,
                "monthlyFlowCredits": 150000
              },
              "availablePromptCredits": 500,
              "availableFlowCredits": 100
            }
          }
        }
        """
        let lines = AntigravityUsageMapper.parseCredits(Data(json.utf8))
        #expect(lines.count == 2)
        #expect(lines.map(\.label) == [AntigravityMetric.promptCreditsLabel, AntigravityMetric.flowCreditsLabel])

        guard case .progress(_, let promptUsed, let promptLimit, .percent, _, _, _) = lines[0],
              case .progress(_, let flowUsed, let flowLimit, .percent, _, _, _) = lines[1]
        else {
            Issue.record("expected percent progress lines, got \(lines)")
            return
        }
        #expect(promptLimit == 100)
        #expect(promptUsed == 99)
        #expect(flowLimit == 100)
        #expect(flowUsed == 100)
    }

    @Test func numericStringsAreAccepted() {
        let json = """
        {"userStatus":{"planStatus":{"planInfo":{"monthlyPromptCredits":"1000"},
         "availablePromptCredits":"250"}}}
        """
        let lines = AntigravityUsageMapper.parseCredits(Data(json.utf8))
        #expect(lines.count == 1)
        guard case .progress(_, let used, _, .percent, _, _, _) = lines[0] else {
            Issue.record("expected a percent progress line")
            return
        }
        #expect(used == 75)
    }

    @Test func noAllowanceMeansNoLine() {
        let json = #"{"userStatus":{"planStatus":{"planInfo":{"planName":"Free"},"availablePromptCredits":0}}}"#
        #expect(AntigravityUsageMapper.parseCredits(Data(json.utf8)).isEmpty)
    }
}
