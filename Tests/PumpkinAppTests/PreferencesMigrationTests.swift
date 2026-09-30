import Foundation
import Testing
@testable import PumpkinApp

@MainActor @Suite struct PreferencesMigrationTests {
    @Test func importsPreferencesEvenWhenWindowMetadataAlreadyExists() {
        let domain = "PumpkinTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.setPersistentDomain(["NSWindow Frame": "saved"], forName: domain)
        Preferences.migrateLegacySettings(defaults: defaults, domain: domain, previous: ["defaultDuration": 3600.0, "watchedFolderPath": "/tmp/Downloads", "hasCompletedOnboarding": true])
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.defaultDuration == 3600)
        #expect(prefs.customFolderPath == "/tmp/Downloads")
        #expect(prefs.hasCompletedOnboarding)
    }

    @Test func currentPreferencesWinAndMigrationRunsOnce() {
        let domain = "PumpkinTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.setPersistentDomain(["defaultDuration": 600.0], forName: domain)
        Preferences.migrateLegacySettings(defaults: defaults, domain: domain, previous: ["defaultDuration": 3600.0, "watchScreenshots": false])
        #expect(defaults.double(forKey: "defaultDuration") == 600)
        #expect(!defaults.bool(forKey: "watchScreenshots"))
        defaults.removeObject(forKey: "watchScreenshots")
        Preferences.migrateLegacySettings(defaults: defaults, domain: domain, previous: ["watchScreenshots": false])
        #expect(defaults.object(forKey: "watchScreenshots") == nil)
    }
}
