import Foundation
import Testing
@testable import PumpkinCore

@Suite struct MigrationTests {
    @Test func copiesPreviousStateAndPreservesBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("ShelfLife/state.json")
        let expected = PersistedState(lastSeenAt: Date(timeIntervalSince1970: 1234), pausedAt: Date(timeIntervalSince1970: 1200))
        try StateStore(url: legacy).save(expected)
        let current = StateStore.migratedURL(in: root)
        #expect(current == root.appendingPathComponent("Pumpkin/state.json"))
        #expect(StateStore(url: current).load() == expected)
        #expect(try Data(contentsOf: legacy) == Data(contentsOf: current))
    }

    @Test func existingPumpkinStateWins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("Pumpkin/state.json")
        let expected = PersistedState(lastSeenAt: Date(timeIntervalSince1970: 9999))
        try StateStore(url: current).save(expected)
        try StateStore(url: root.appendingPathComponent("ShelfLife/state.json")).save(PersistedState())
        #expect(StateStore(url: StateStore.migratedURL(in: root)).load() == expected)
    }

    @Test func failedCopyFallsBackToPreviousState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("ShelfLife/state.json")
        try StateStore(url: legacy).save(PersistedState())
        try Data("blocked".utf8).write(to: root.appendingPathComponent("Pumpkin"))
        #expect(StateStore.migratedURL(in: root) == legacy)
    }
}
