import XCTest
@testable import OpenUsage

/// The resource bundle lookup must prefer the bundle this package builds today
/// (`OpenQuota_OpenUsage.bundle`) over the pre-rebrand copy a stale `.build` directory still carries
/// (`OpenUsage_OpenUsage.bundle`). The legacy copy is out of date — it ships without the newest
/// provider marks (e.g. Mistral) and without the current pricing supplement — so letting it win makes
/// a freshly built app load old resources.
final class ResourceBundleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openquota-resource-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testPrefersCurrentBundleNameOverLegacyCopyInTheSameDirectory() throws {
        try makeBundle(named: "OpenUsage_OpenUsage.bundle", withSupplement: true)
        try makeBundle(named: "OpenQuota_OpenUsage.bundle", withSupplement: true)

        let bundle = try XCTUnwrap(Bundle.locateOpenUsageResourceBundles(in: [root]))

        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "OpenQuota_OpenUsage.bundle")
        XCTAssertTrue(Bundle.openUsageResourceBundleNames.first == "OpenQuota_OpenUsage.bundle")
    }

    func testFallsBackToLegacyNameWhenItIsTheOnlyBundle() throws {
        try makeBundle(named: "OpenUsage_OpenUsage.bundle", withSupplement: true)

        let bundle = try XCTUnwrap(Bundle.locateOpenUsageResourceBundles(in: [root]))

        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "OpenUsage_OpenUsage.bundle")
    }

    func testSkipsAnEmptySameNamedDirectoryAndKeepsSearching() throws {
        try makeBundle(named: "OpenQuota_OpenUsage.bundle", withSupplement: false)
        try makeBundle(named: "OpenUsage_OpenUsage.bundle", withSupplement: true)

        let bundle = try XCTUnwrap(Bundle.locateOpenUsageResourceBundles(in: [root]))

        XCTAssertEqual(bundle.bundleURL.lastPathComponent, "OpenUsage_OpenUsage.bundle")
    }

    func testReturnsNilWhenNoCandidateCarriesTheSupplement() throws {
        try makeBundle(named: "OpenQuota_OpenUsage.bundle", withSupplement: false)

        XCTAssertNil(Bundle.locateOpenUsageResourceBundles(in: [root]))
    }

    /// The Mistral mark this repo ships must be reachable through the resolved resource bundle —
    /// the missing icon was a stale bundle, not a missing file.
    func testResolvedBundleCarriesTheMistralMark() {
        XCTAssertNotNil(
            Bundle.openUsageResources.url(
                forResource: "mistral", withExtension: "svg", subdirectory: "ProviderIcons"
            )
        )
    }

    private func makeBundle(named name: String, withSupplement: Bool) throws {
        let resources = root
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        guard withSupplement else { return }
        try Data(#"{"updated_at":"2026-11-24T00:00:00Z"}"#.utf8)
            .write(to: resources.appendingPathComponent("pricing_supplement.json"))
    }
}
