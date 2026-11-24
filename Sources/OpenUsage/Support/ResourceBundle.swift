import Foundation

extension Bundle {
    /// Candidate names for the bundle carrying OpenQuota's copied resources (provider SVGs, pricing
    /// supplement + snapshots), most current first.
    ///
    /// SwiftPM names a target's resource bundle `<Package>_<Target>.bundle`, so the OpenQuota rebrand
    /// renamed this one from `OpenUsage_OpenUsage.bundle` to `OpenQuota_OpenUsage.bundle`. A `.build`
    /// directory that predates the rename still holds the old bundle, and the packaging scripts stage
    /// every `*.bundle` they find — so an app built on top of a stale `.build` ships both, and the legacy
    /// one is out of date (it arrived without the newest provider marks and pricing supplement). Trying
    /// the current name first keeps that stale copy from shadowing the real one. The legacy name stays in
    /// the list so a build that only has the old bundle still resolves.
    static let openUsageResourceBundleNames = ["OpenQuota_OpenUsage.bundle", "OpenUsage_OpenUsage.bundle"]

    /// The bundle carrying OpenQuota's copied resources (provider SVGs, pricing supplement + snapshots).
    ///
    /// SwiftPM generates `Bundle.module` for an executable target that only looks two places: next to
    /// `Bundle.main.bundleURL` (which, for a packaged `.app`, is the app root) and a path into the build
    /// tree baked in at compile time. Neither resolves in a shipped `.app`, where the resource bundle
    /// lives in `Contents/Resources` — so `Bundle.module` hits its `fatalError` and the app crashes on
    /// launch. (A locally built app appears to work only because the baked-in build path still exists on
    /// the build machine.)
    ///
    /// This accessor looks where the resource bundle actually ships first, and only falls back to
    /// `Bundle.module` for `swift run` / `swift test`, where the build path is valid.
    static let openUsageResources: Bundle = {
        let containingAppResources = Bundle.main.executableURL
            .flatMap(ContainingAppBundle.url(for:))?
            .appendingPathComponent("Contents/Resources", isDirectory: true)
        let searchBases = [
            Bundle.main.resourceURL,                          // packaged .app: Contents/Resources
            Bundle.main.bundleURL,                            // bundle beside the app root
            containingAppResources,                           // bundled CLI: helper -> app Resources
            Bundle(for: ResourceBundleToken.self).resourceURL,
            Bundle(for: ResourceBundleToken.self).bundleURL
        ].compactMap { $0 }
        return locateOpenUsageResourceBundles(in: searchBases) ?? .module
    }()

    /// First valid resource bundle found under `bases`, trying each candidate name per base so the
    /// current build's bundle wins over a stale legacy copy sitting in the same directory.
    static func locateOpenUsageResourceBundles(in bases: [URL]) -> Bundle? {
        for base in bases {
            for name in openUsageResourceBundleNames {
                // `Bundle(url:)` succeeds for ANY directory at the path, not only a real resources
                // bundle. A stale/empty same-named directory left by an earlier build would otherwise
                // shadow the real one and make every resource URL nil (SF-Symbol icon fallbacks + a
                // thrown Cursor manifest). Skip it loudly and keep searching.
                guard let bundle = Bundle(url: base.appendingPathComponent(name)) else { continue }
                if isValidOpenUsageResourceBundle(bundle) {
                    return bundle
                }
                AppLog.warn(.config, "ignoring resource bundle at \(base.lastPathComponent): missing expected resources")
            }
        }
        return nil
    }
}

/// Sentinel check: a valid OpenQuota resource bundle carries the bundled pricing supplement at its
/// root (`.copy("Resources/pricing_supplement.json")`). Uses the same lookup the pricing store relies
/// on, so it can never reject the real shipped bundle.
private func isValidOpenUsageResourceBundle(_ bundle: Bundle) -> Bool {
    bundle.url(forResource: "pricing_supplement", withExtension: "json") != nil
}

private final class ResourceBundleToken {}
