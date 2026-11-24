import Foundation

@MainActor
final class MistralProvider: ProviderRuntime {
    let provider = Provider(
        id: "mistral",
        displayName: "Mistral",
        icon: .providerMark("mistral"),
        links: [
            ProviderLink(label: "Usage", url: "https://admin.mistral.ai/organization/usage"),
            ProviderLink(label: "Status", url: "https://status.mistral.ai")
        ]
    )

    let authStore: MistralAuthStore
    let usageClient: MistralUsageClient
    let now: @Sendable () -> Date

    init(
        authStore: MistralAuthStore = MistralAuthStore(),
        usageClient: MistralUsageClient = MistralUsageClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authStore = authStore
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "mistral.api", provider: provider, title: "API Allowance"),
            .percent(id: "mistral.vibe", provider: provider, title: "Vibe & Studio Allowance"),
            .badge(id: "mistral.payg", provider: provider, title: "Pay-as-you-go")
        ]
    }

    func hasLocalCredentials() async -> Bool {
        // Same source as `refresh()`: a stored or environment-exported API key.
        await loadOffMainActor { [authStore] in authStore.loadAPIKey() } != nil
    }

    func refresh() async -> ProviderSnapshot {
        guard let auth = await loadOffMainActor({ [authStore] in authStore.loadAPIKey() }) else {
            return ProviderSnapshot.error(provider: provider, error: MistralAuthError.missingKey)
        }

        // The budget call carries every metric line; subscription only adds the plan badge, so a
        // failed subscription lookup degrades quietly while a failed budget call is the real error.
        let budget = await load { try await usageClient.fetchBudget(apiKey: auth.apiKey) }
        let subscription = await load { try await usageClient.fetchSubscription(apiKey: auth.apiKey) }

        var plan: String?
        if case .success(let data) = subscription {
            plan = MistralUsageMapper.planName(from: data)
        }

        if case .success(let data) = budget {
            let lines = MistralUsageMapper.budgetLines(from: data)
            if !lines.isEmpty {
                return ProviderSnapshot.make(provider: provider, plan: plan, lines: lines, refreshedAt: now())
            }
            return ProviderSnapshot.error(provider: provider, error: MistralUsageError.invalidResponse)
        }

        switch budget {
        case .authFailure:
            return ProviderSnapshot.error(provider: provider, error: MistralAuthError.invalidKey)
        case .failed(let error):
            return ProviderSnapshot.error(provider: provider, error: error)
        case .success:
            return ProviderSnapshot.error(provider: provider, error: MistralUsageError.invalidResponse)
        }
    }

    /// Run one endpoint call and classify the outcome: a parsed data object on 2xx, an auth failure on
    /// 401/403, or a typed failure for any other non-2xx, transport error, or unparsable body.
    private func load(_ call: () async throws -> HTTPResponse) async -> EndpointResult {
        do {
            let response = try await call()
            if response.statusCode == 401 || response.statusCode == 403 { return .authFailure }
            guard (200..<300).contains(response.statusCode) else {
                return .failed(.requestFailed(response.statusCode))
            }
            guard let data = ProviderParse.jsonObject(response.body) else {
                return .failed(.invalidResponse)
            }
            return .success(data)
        } catch {
            return .failed(.connectionFailed)
        }
    }
}

extension MistralProvider: APIKeyManaging {
    var apiKeyStatus: APIKeyStatus { authStore.keyStatus() }
    func currentAPIKey() -> String? { authStore.currentAPIKey() }
    func saveAPIKey(_ key: String) throws { try authStore.saveAPIKey(key) }
    func deleteAPIKey() throws { try authStore.deleteAPIKey() }
}

private enum EndpointResult {
    case success([String: Any])
    case authFailure
    case failed(MistralUsageError)
}
