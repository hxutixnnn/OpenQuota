import XCTest
@testable import OpenUsage

/// Layout defaults for Devin's quota meters. Uses the real provider's registry with the real
/// `DefaultLayout` seeds, so a change to the pins is caught here.
@MainActor
final class DevinLayoutTests: XCTestCase {

    func testFreshDefaultsPinDailyAndWeeklyOnly() {
        let store = makeStore("FreshDefaults")

        XCTAssertEqual(store.placed.map(\.descriptorID), [
            "devin.daily", "devin.weekly", "devin.extra"
        ])
        XCTAssertEqual(store.pinnedMetricIDs, ["devin.daily", "devin.weekly"])

        let group = store.customizeGroups.first { $0.provider.id == "devin" }
        XCTAssertEqual(group?.alwaysShownMetrics.map(\.id), ["devin.daily", "devin.weekly"])
        XCTAssertEqual(group?.expandedMetrics.map(\.id), ["devin.extra"])
    }

    func testSavedPinsAreNotReseeded() {
        let defaults = makeDefaults("SavedPins")
        defaults.set(["devin.daily"], forKey: "layout.menuBarPins")

        let store = LayoutStore(registry: .devinOnly, defaults: defaults, storageKey: "layout")

        XCTAssertEqual(store.pinnedMetricIDs, ["devin.daily"])
    }

    // MARK: - Fixtures

    private func makeStore(_ name: String) -> LayoutStore {
        LayoutStore(registry: .devinOnly, defaults: makeDefaults(name), storageKey: "layout")
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suiteName = "OpenUsageTests.DevinLayout.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private extension WidgetRegistry {
    @MainActor
    static var devinOnly: WidgetRegistry { .from([DevinProvider()]) }
}
