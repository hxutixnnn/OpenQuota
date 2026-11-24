import Foundation

struct MistralUsageClient: Sendable {
    static let budgetURL = "https://api.mistral.ai/v1/billing/budget"
    static let subscriptionURL = "https://api.mistral.ai/v1/billing/subscription"

    var http: any HTTPClient

    init(http: any HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    /// Organization monthly allowances: `api_budget` and `vibe_budget`, each carrying
    /// `usage_percentage`, `initial_budget` (EUR), `reset_at`, and `payg_enabled`.
    func fetchBudget(apiKey: String) async throws -> HTTPResponse {
        try await get(Self.budgetURL, apiKey: apiKey)
    }

    /// Plan name and per-service pay-as-you-go flags. Fetched independently from the budget so a
    /// gated or missing subscription call never blanks the meters.
    func fetchSubscription(apiKey: String) async throws -> HTTPResponse {
        try await get(Self.subscriptionURL, apiKey: apiKey)
    }

    private func get(_ urlString: String, apiKey: String) async throws -> HTTPResponse {
        guard let url = URL(string: urlString) else {
            throw MistralUsageError.invalidResponse
        }

        return try await http.send(HTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json"
            ],
            timeout: 15
        ))
    }
}

enum MistralUsageError: Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Couldn't reach Mistral. Check your connection."
        case .invalidResponse:
            return "Mistral usage data unavailable. Try again later."
        case .requestFailed(let status):
            return "Mistral request failed (HTTP \(status))."
        }
    }
}
