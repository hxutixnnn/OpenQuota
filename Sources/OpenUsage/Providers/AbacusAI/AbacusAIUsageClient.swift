import Foundation

enum AbacusAIError: LocalizedError, Sendable {
    case cliNotFound
    case timedOut
    case invalidResponse
    case noMeters

    var errorDescription: String? {
        switch self {
        case .cliNotFound: "abacusai CLI not found at ~/.abacusai/bin/abacusai."
        case .timedOut: "abacusai CLI did not report usage before timing out."
        case .invalidResponse: "abacusai CLI returned an unreadable usage payload."
        case .noMeters: "Abacus.AI reported no usage meter for this organization."
        }
    }
}

/// Reads the usage the `abacusai` CLI already tracks for the signed-in account.
///
/// The CLI exposes it over its stream-json protocol as a `get_usage` control request; its answer
/// carries the same `usage` object (plan + meters) the CLI shows in `/usage`. That is richer than the
/// per-user pools on `/api/_getCodeLlmUsage`, which answer null for enterprise orgs. No turn is
/// started, so no credits are spent.
struct AbacusAIUsageClient: Sendable {
    static let requestID = "openusage-usage"

    static func resolveBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.abacusai/bin/abacusai",
            "\(home)/.local/bin/abacusai",
            "/opt/homebrew/bin/abacusai",
            "/usr/local/bin/abacusai"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func fetchUsage(timeout: TimeInterval = 20) async throws -> Data {
        guard let binary = Self.resolveBinary() else {
            throw AbacusAIError.cliNotFound
        }
        return try await Task.detached(priority: .userInitiated) {
            // Process is safe to terminate from another thread; the box only satisfies Sendable.
            let box = ProcessBox()
            let process = box.process
            process.executableURL = binary
            process.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json"]
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()

            let request: [String: Any] = [
                "type": "control_request",
                "request_id": Self.requestID,
                "request": ["subtype": "get_usage"]
            ]
            if let payload = try? JSONSerialization.data(withJSONObject: request) {
                try? stdinPipe.fileHandleForWriting.write(contentsOf: payload + Data([0x0A]))
            }
            // Closing stdin asks the CLI to answer and exit on its own.
            stdinPipe.fileHandleForWriting.closeFile()

            let watchdog = DispatchWorkItem {
                if box.process.isRunning { box.process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            var usage: [String: Any]?

            readLoop: while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                        continue
                    }
                    if let found = Self.usageObject(from: object) {
                        usage = found
                        break readLoop
                    }
                }
            }

            watchdog.cancel()
            if process.isRunning { process.terminate() }

            guard let usage,
                  let encoded = try? JSONSerialization.data(withJSONObject: ["usage": usage]) else {
                throw AbacusAIError.timedOut
            }
            return encoded
        }.value
    }

    /// Sendable carrier for the CLI process so the watchdog can stop it from another queue.
    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    /// Pulls the `usage` object out of either wire shape: the CLI's control-response answer to
    /// `get_usage`, or a `usage_changed` system event (older CLI builds only sent that during a turn).
    private static func usageObject(from object: [String: Any]) -> [String: Any]? {
        if object["type"] as? String == "control_response",
           let response = object["response"] as? [String: Any],
           response["subtype"] as? String == "success",
           let body = response["response"] as? [String: Any],
           let usage = body["usage"] as? [String: Any] {
            return usage
        }
        if object["type"] as? String == "system",
           object["subtype"] as? String == "usage_changed",
           let usage = object["usage"] as? [String: Any] {
            return usage
        }
        return nil
    }
}
