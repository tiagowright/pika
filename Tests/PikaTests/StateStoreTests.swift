import Foundation
import Testing
@testable import Pika

@MainActor @Suite struct StateStoreTests {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pika-state-\(UUID().uuidString).json")

    @Test func roundTrips() throws {
        let store = StateStore(fileURL: url)
        #expect(store.state == AppState())
        store.update {
            $0.onboardingVersion = 1
            $0.skipped = ["chrome"]
            $0.chromeAutomation = .denied
        }
        let reloaded = StateStore(fileURL: url)
        #expect(reloaded.state.onboardingVersion == 1)
        #expect(reloaded.state.skipped == ["chrome"])
        #expect(reloaded.state.chromeAutomation == .denied)
    }

    @Test func toleratesMissingAndUnknownFields() throws {
        try Data(#"{"onboardingVersion": 2, "chromeAutomation": "sometimes", "future": true}"#.utf8).write(to: url)
        let store = StateStore(fileURL: url)
        #expect(store.state.onboardingVersion == 2)
        #expect(store.state.chromeAutomation == nil)
        #expect(store.state.skipped.isEmpty)
    }

    @Test func survivesGarbage() throws {
        try Data("not json".utf8).write(to: url)
        #expect(StateStore(fileURL: url).state == AppState())
    }
}
