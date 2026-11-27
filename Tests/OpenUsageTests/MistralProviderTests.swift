import XCTest
@testable import OpenUsage

final class MistralAuthStoreTests: XCTestCase {
    func testLoadsConfigBeforeEnvironmentAndSkipsBlankValues() {
        let primary = MistralAuthStore.configPaths[0]
        let alternate = MistralAuthStore.configPaths[1]
        let cases: [(name: String, files: [String: String], environment: [String: String], expected: String)] = [
            ("saved override", [primary: #"{"apiKey":"ms-file"}"#], ["MISTRAL_API_KEY": "ms-env"], "ms-file"),
            ("environment fallback", [:], ["MISTRAL_API_KEY": "ms-env"], "ms-env"),
            ("legacy JSON key", [primary: #"{"api_key":"ms-json"}"#], [:], "ms-json"),
            ("trimmed plain text", [alternate: "  ms-plain\n"], [:], "ms-plain"),
            ("blank config", [primary: "   "], ["MISTRAL_API_KEY": "ms-env"], "ms-env")
        ]

        for entry in cases {
            let store = MistralAuthStore(files: FakeFiles(entry.files), environment: FakeEnvironment(entry.environment))
            XCTAssertEqual(store.loadAPIKey()?.apiKey, entry.expected, entry.name)
        }
    }

    func testReturnsNilWhenNoKeyAnywhere() {
        let store = MistralAuthStore(files: FakeFiles(), environment: FakeEnvironment())
        XCTAssertNil(store.loadAPIKey())
    }

    func testSaveAPIKeyWritesTrimmedJSONConfigFile() throws {
        let files = FakeFiles()
        let store = MistralAuthStore(files: files, environment: FakeEnvironment())

        try store.saveAPIKey("  ms-new  ")

        XCTAssertEqual(files.files[MistralAuthStore.configPaths[0]], #"{"apiKey":"ms-new"}"#)
        XCTAssertEqual(store.loadAPIKey()?.apiKey, "ms-new")
    }

    func testSavedKeyOverridesEnvironment() throws {
        let files = FakeFiles()
        let store = MistralAuthStore(files: files, environment: FakeEnvironment(["MISTRAL_API_KEY": "ms-env"]))

        try store.saveAPIKey("ms-saved")

        XCTAssertEqual(store.loadAPIKey()?.apiKey, "ms-saved")
        XCTAssertEqual(store.keyStatus(), .overrideActive)
    }

    func testDeleteClearsAllPathsWithEnvironmentFallback() throws {
        let files = FakeFiles([
            MistralAuthStore.configPaths[0]: #"{"apiKey":"ms-primary"}"#,
            MistralAuthStore.configPaths[1]: "ms-alt"
        ])
        let store = MistralAuthStore(files: files, environment: FakeEnvironment(["MISTRAL_API_KEY": "ms-env"]))

        try store.deleteAPIKey()

        for path in MistralAuthStore.configPaths { XCTAssertNil(files.files[path], path) }
        XCTAssertEqual(store.loadAPIKey()?.apiKey, "ms-env")
        XCTAssertEqual(store.keyStatus(), .fromEnvironment)
    }
}

final class MistralUsageMapperTests: XCTestCase {
    func testBudgetLinesGiveBothMetersAndPaygBadge() throws {
        let lines = MistralUsageMapper.budgetLines(from: [
            "api_budget": ["usage_percentage": 0.0036821, "initial_budget": 25.5,
                           "reset_at": "2026-12-01T00:00:00Z", "payg_enabled": false],
            "vibe_budget": ["usage_percentage": 42.0, "initial_budget": 255.0,
                            "reset_at": "2026-12-01T00:00:00Z", "payg_enabled": false]
        ])

        let api = try XCTUnwrap(progress(lines, "API Allowance"))
        XCTAssertEqual(api.used, 0.0036821, accuracy: 0.0001)
        XCTAssertEqual(api.limit, 100)
        XCTAssertNotNil(api.resetsAt)
        let vibe = try XCTUnwrap(progress(lines, "Vibe & Studio Allowance"))
        XCTAssertEqual(vibe.used, 42.0, accuracy: 0.001)
        XCTAssertEqual(badgeText(lines, "Pay-as-you-go"), "Disabled")
    }

    func testPaygBadgeEnabledWhenEitherBudgetPays() {
        let lines = MistralUsageMapper.budgetLines(from: [
            "api_budget": ["usage_percentage": 0, "initial_budget": 25.5, "payg_enabled": true],
            "vibe_budget": ["usage_percentage": 0, "initial_budget": 255.0, "payg_enabled": false]
        ])
        XCTAssertEqual(badgeText(lines, "Pay-as-you-go"), "Enabled")
    }

    func testMissingVibeBudgetStillShowsAPIMeter() {
        let lines = MistralUsageMapper.budgetLines(from: [
            "api_budget": ["usage_percentage": 10, "initial_budget": 25.5]
        ])
        XCTAssertNotNil(progress(lines, "API Allowance"))
        XCTAssertNil(progress(lines, "Vibe & Studio Allowance"))
    }

    func testEmptyBudgetProducesNoLines() {
        XCTAssertTrue(MistralUsageMapper.budgetLines(from: ["foo": "bar"]).isEmpty)
    }

    /// The pacing window is the real billing month that ends at `reset_at`, not a 30-day stand-in:
    /// November and July run 30 and 31 days, February 2027 runs 28.
    func testAllowanceWindowsAreCalendarMonths() throws {
        let cases: [(reset: String, days: Int)] = [
            ("2026-12-01T00:00:00Z", 30),
            ("2026-08-01T00:00:00Z", 31),
            ("2027-03-01T00:00:00Z", 28)
        ]

        for testCase in cases {
            let lines = MistralUsageMapper.budgetLines(from: [
                "api_budget": ["usage_percentage": 1, "initial_budget": 25.5, "reset_at": testCase.reset]
            ])
            let api = try XCTUnwrap(progress(lines, "API Allowance"))
            XCTAssertEqual(api.period, testCase.days * MetricPeriod.dayMs, testCase.reset)
        }
    }

    func testAllowanceWithoutResetDateCarriesNoWindow() {
        let lines = MistralUsageMapper.budgetLines(from: [
            "api_budget": ["usage_percentage": 10, "initial_budget": 25.5]
        ])
        XCTAssertNil(progress(lines, "API Allowance")?.period)
    }

    func testPlanNameTitleCased() {
        XCTAssertEqual(MistralUsageMapper.planName(from: ["plan_name": "INDIVIDUAL"]), "Individual")
        XCTAssertNil(MistralUsageMapper.planName(from: [:]))
    }

    private func progress(
        _ lines: [MetricLine],
        _ label: String
    ) -> (used: Double, limit: Double, resetsAt: Date?, period: Int?)? {
        guard case .progress(_, let used, let limit, _, let resetsAt, let period, _) = lines.first(where: { $0.label == label }) else {
            return nil
        }
        return (used, limit, resetsAt, period)
    }

    private func badgeText(_ lines: [MetricLine], _ label: String) -> String? {
        guard case .badge(_, let text, _, _) = lines.first(where: { $0.label == label }) else {
            return nil
        }
        return text
    }
}

/// Locks the user-visible half of the monthly window: a Mistral allowance row can now project where
/// its spend lands at reset, where a reset date with no period could only report its level band.
@MainActor
final class MistralPaceTests: XCTestCase {
    func testAllowanceRowPacesAcrossItsMonthlyWindow() async throws {
        let reset = "2026-12-15T12:00:00Z"
        let resetsAt = try XCTUnwrap(OpenUsageISO8601.date(from: reset))
        let lines = MistralUsageMapper.budgetLines(from: [
            "api_budget": ["usage_percentage": 42.0, "initial_budget": 25.5, "reset_at": reset]
        ])
        let (store, descriptor) = await makeStore(lines: lines)

        // Halfway through the window at 42% used → ~84% at reset → ~16% left to spare.
        let halfway = resetsAt.addingTimeInterval(-15 * 24 * 60 * 60)
        XCTAssertEqual(store.data(for: descriptor).meterState(now: halfway).tooltip, "~16% left at reset")
    }

    /// Runs the mapper's lines through the real resolve path every provider funnels through.
    private func makeStore(lines: [MetricLine]) async -> (WidgetDataStore, WidgetDescriptor) {
        let provider = Provider(id: "mistral", displayName: "Mistral", icon: .providerMark("mistral"))
        let descriptor = WidgetDescriptor(
            id: "mistral.api",
            providerID: provider.id,
            metricLabel: "API Allowance",
            sample: WidgetData(title: "API Allowance", icon: provider.icon, kind: .percent, used: 0, limit: 100)
        )
        let runtime = TestProviderRuntime(
            provider: provider,
            descriptors: [descriptor],
            snapshot: ProviderSnapshot(
                providerID: provider.id,
                displayName: provider.displayName,
                lines: lines
            )
        )
        let suiteName = "OpenUsageTests.MistralPace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let cache = ProviderSnapshotCache(userDefaults: defaults, storageKey: "snapshots", ttl: 600, now: { Date() })
        let store = WidgetDataStore(
            registry: WidgetRegistry(providers: [provider], descriptors: [descriptor]),
            providers: [runtime],
            cache: cache,
            defaults: defaults
        )
        await store.refreshAll()
        return (store, descriptor)
    }
}

@MainActor
final class MistralProviderTests: XCTestCase {
    func testRefreshMapsBudgetAndPlan() async throws {
        let provider = MistralProvider(
            authStore: makeAuthStore(key: "ms-test"),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { request in
                XCTAssertEqual(request.headers["Authorization"], "Bearer ms-test")
                if request.url.absoluteString == MistralUsageClient.budgetURL {
                    return mistralJSONResponse([
                        "api_budget": ["usage_percentage": 0.5, "initial_budget": 25.5,
                                       "reset_at": "2026-12-01T00:00:00Z", "payg_enabled": false],
                        "vibe_budget": ["usage_percentage": 0, "initial_budget": 255.0,
                                        "reset_at": "2026-12-01T00:00:00Z", "payg_enabled": false]
                    ])
                }
                return mistralJSONResponse(["plan_name": "INDIVIDUAL"])
            }),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let snapshot = await provider.refresh()

        XCTAssertEqual(snapshot.plan, "Individual")
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertNotNil(snapshot.line(label: "API Allowance"))
        XCTAssertNotNil(snapshot.line(label: "Vibe & Studio Allowance"))
        XCTAssertNotNil(snapshot.line(label: "Pay-as-you-go"))
    }

    func testRefreshKeepsMetersWhenSubscriptionFails() async {
        let provider = MistralProvider(
            authStore: makeAuthStore(key: "ms-test"),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { request in
                if request.url.absoluteString == MistralUsageClient.budgetURL {
                    return mistralJSONResponse(["api_budget": ["usage_percentage": 3, "initial_budget": 25.5]])
                }
                throw MistralUsageError.connectionFailed
            })
        )

        let snapshot = await provider.refresh()

        XCTAssertNil(snapshot.plan)
        XCTAssertFalse(snapshot.lines.contains { $0.isError })
        XCTAssertNotNil(snapshot.line(label: "API Allowance"))
    }

    func testRefreshWithoutKeyReportsNotLoggedIn() async {
        let provider = MistralProvider(
            authStore: MistralAuthStore(files: FakeFiles(), environment: FakeEnvironment()),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { _ in
                XCTFail("should not hit the network without a key")
                return mistralJSONResponse([:])
            })
        )

        let snapshot = await provider.refresh()

        XCTAssertEqual(snapshot.lines.first?.label, "Error")
        XCTAssertEqual(snapshot.errorCategory, .notLoggedIn)
    }

    func testRefreshOnAuthFailureReportsInvalidKey() async {
        let provider = MistralProvider(
            authStore: makeAuthStore(key: "ms-bad"),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { _ in
                HTTPResponse(statusCode: 401, headers: [:], body: Data("{}".utf8))
            })
        )

        let snapshot = await provider.refresh()

        XCTAssertEqual(snapshot.errorCategory, .authInvalid)
    }

    func testRefreshOnBudgetFailureReportsError() async {
        let provider = MistralProvider(
            authStore: makeAuthStore(key: "ms-test"),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { request in
                if request.url.absoluteString == MistralUsageClient.budgetURL {
                    return HTTPResponse(statusCode: 500, headers: [:], body: Data("{}".utf8))
                }
                return mistralJSONResponse(["plan_name": "INDIVIDUAL"])
            })
        )

        let snapshot = await provider.refresh()

        XCTAssertEqual(snapshot.errorCategory, .http5xx)
    }

    func testProviderAPIKeyManagingDelegatesToAuthStore() throws {
        let files = FakeFiles()
        let provider = MistralProvider(
            authStore: MistralAuthStore(files: files, environment: FakeEnvironment(["MISTRAL_API_KEY": "ms-env"])),
            usageClient: MistralUsageClient(http: RoutingHTTPClient { _ in mistralJSONResponse([:]) })
        )

        XCTAssertEqual(provider.apiKeyStatus, .fromEnvironment)
        XCTAssertEqual(provider.currentAPIKey(), "ms-env")

        try provider.saveAPIKey("ms-saved")
        XCTAssertEqual(provider.apiKeyStatus, .overrideActive)
        XCTAssertEqual(provider.currentAPIKey(), "ms-saved")

        try provider.deleteAPIKey()
        XCTAssertEqual(provider.apiKeyStatus, .fromEnvironment)
    }

    private func makeAuthStore(key: String) -> MistralAuthStore {
        MistralAuthStore(files: FakeFiles(), environment: FakeEnvironment(["MISTRAL_API_KEY": key]))
    }
}

private func mistralJSONResponse(_ object: [String: Any]) -> HTTPResponse {
    let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    return HTTPResponse(statusCode: 200, headers: [:], body: body)
}
