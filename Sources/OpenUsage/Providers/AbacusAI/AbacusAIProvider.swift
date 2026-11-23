import Foundation

@MainActor
final class AbacusAIProvider: ProviderRuntime {
    let provider = Provider(
        id: "abacus",
        displayName: "Abacus.AI",
        icon: .providerMark("abacusai"),
        links: [
            ProviderLink(label: "Dashboard", url: "https://apps.abacus.ai/")
        ]
    )

    let usageClient: AbacusAIUsageClient
    let now: @Sendable () -> Date

    init(
        usageClient: AbacusAIUsageClient = AbacusAIUsageClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .boundedCount(
                id: "abacus.monthly",
                provider: provider,
                title: "Monthly Credits",
                metricLabel: "Monthly Credits",
                limit: 30_000,
                suffix: "credits",
                periodDurationMs: AbacusAIUsageMapper.monthlyPeriodMs
            )
            .exportingLimit("monthlyCredits", unit: "credits")
        ]
    }

    func hasLocalCredentials() async -> Bool {
        await loadOffMainActor { AbacusAIUsageClient.resolveBinary() != nil }
    }

    func refresh() async -> ProviderSnapshot {
        do {
            let data = try await usageClient.fetchUsage()
            let mapped = try AbacusAIUsageMapper.map(data, now: now())
            return ProviderSnapshot.make(provider: provider, plan: mapped.plan, lines: mapped.lines, refreshedAt: now())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }
}
