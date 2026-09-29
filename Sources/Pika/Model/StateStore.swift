import Foundation
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "state")

/// Pika's own bookkeeping — not settings, so not in config.toml
/// (SETTINGS.md §1.1). Lives in `state.json` beside mru.json.
struct AppState: Codable, Equatable {
    /// The onboarding version last completed; 0 means never (SHIPPING.md §4.3).
    var onboardingVersion = 0
    var onboardingCompletedAt: Date?
    /// Optional checklist items the user chose to skip (SETTINGS.md §2.4.4).
    var skipped: [String] = []
    /// The last Automation answer seen for Chrome, so "denied" can still be
    /// shown while Chrome isn't running and can't be asked.
    var chromeAutomation: Grant?

    init() {}

    // Every field optional on disk, so older or hand-edited files still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboardingVersion = try c.decodeIfPresent(Int.self, forKey: .onboardingVersion) ?? 0
        onboardingCompletedAt = try c.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        skipped = try c.decodeIfPresent([String].self, forKey: .skipped) ?? []
        chromeAutomation = try? c.decodeIfPresent(Grant.self, forKey: .chromeAutomation)
    }
}

/// Main thread only.
final class StateStore {
    static let shared = StateStore()

    private(set) var state: AppState
    private let fileURL: URL

    /// Internal rather than private so tests can point it at a temp file.
    init(fileURL: URL = AppPaths.supportDirectory.appendingPathComponent("state.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            do {
                state = try Self.decoder.decode(AppState.self, from: data)
            } catch {
                log.error("state.json is unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
                state = AppState()
            }
        } else {
            state = AppState()
        }
    }

    func update(_ change: (inout AppState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(next).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save state.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
