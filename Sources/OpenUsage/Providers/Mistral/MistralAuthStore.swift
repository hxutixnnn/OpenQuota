import Foundation

struct MistralAuth: Hashable, Sendable {
    var apiKey: String
}

enum MistralAuthError: Error, LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case saveFailed
    case deleteFailed

    init(_ failure: UserAPIKeyStore.Failure) {
        switch failure {
        case .missingKey: self = .missingKey
        case .saveFailed: self = .saveFailed
        case .deleteFailed: self = .deleteFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Mistral API key. Set MISTRAL_API_KEY or add it to ~/.config/openquota/mistral.json."
        case .invalidKey:
            return "Mistral API key invalid. Check your key at admin.mistral.ai."
        case .saveFailed:
            return "Couldn't save the Mistral API key."
        case .deleteFailed:
            return "Couldn't remove the saved Mistral API key."
        }
    }
}

/// Reads a Mistral API key the user has already placed on the machine. Mistral has no companion CLI or
/// app that stashes a credential, so the key comes from an environment variable or a small config file.
/// A GUI app launched from Finder/Dock doesn't inherit the interactive shell environment, so
/// `ProcessEnvironmentReader` captures the login shell's environment at launch (see
/// `LoginShellEnvironment`) — meaning an env var exported in a shell profile is honored even in a
/// packaged build; the config file remains the explicit path.
struct MistralAuthStore: Sendable {
    /// Config files checked in order; first readable key wins. JSON (`apiKey` / `api_key` / `key`) or a
    /// plain-text file containing only the key.
    static let configPaths = [
        "~/.config/openquota/mistral.json",
        "~/.config/mistral/key.json"
    ]
    /// Environment variables checked in order. `MISTRAL_API_KEY` is the de-facto standard.
    static let environmentNames = ["MISTRAL_API_KEY"]

    private let store: UserAPIKeyStore

    init(
        files: TextFileAccessing = LocalTextFileAccessor(),
        environment: EnvironmentReading = ProcessEnvironmentReader()
    ) {
        store = UserAPIKeyStore(
            configPaths: Self.configPaths,
            environmentNames: Self.environmentNames,
            files: files,
            environment: environment,
            makeError: { MistralAuthError($0) }
        )
    }

    func loadAPIKey() -> MistralAuth? { store.loadKey().map(MistralAuth.init(apiKey:)) }
    func currentAPIKey() -> String? { store.loadKey() }
    func keyStatus() -> APIKeyStatus { store.keyStatus() }
    func saveAPIKey(_ key: String) throws { try store.saveKey(key) }
    func deleteAPIKey() throws { try store.deleteKey() }
}
