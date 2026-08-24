import Testing
import Foundation
@testable import romm

// MARK: - UserDefaultsChangelogSeenStore

struct ChangelogSeenStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // An absent key must come back as nil, not 0, so the use case can
    // distinguish "never opened" from "opened, saw build 0".
    @Test func defaultLastSeenBuildIsNil() {
        let store = UserDefaultsChangelogSeenStore(userDefaults: makeDefaults())
        #expect(store.lastSeenBuild == nil)
    }

    @Test func writtenBuildRoundTrips() {
        let defaults = makeDefaults()
        let store = UserDefaultsChangelogSeenStore(userDefaults: defaults)
        store.lastSeenBuild = 49
        #expect(store.lastSeenBuild == 49)
    }

    // The value must survive across instances that share the same UserDefaults suite,
    // simulating app restarts where a new store object is created each time.
    @Test func buildPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = UserDefaultsChangelogSeenStore(userDefaults: defaults)
        store1.lastSeenBuild = 49

        let store2 = UserDefaultsChangelogSeenStore(userDefaults: defaults)
        #expect(store2.lastSeenBuild == 49)
    }

    // Setting to nil must write 0 internally so the next read comes back as nil,
    // not a leftover build number. This is the "reset" path after a clean install.
    @Test func settingNilClearsTheBuild() {
        let defaults = makeDefaults()
        let store = UserDefaultsChangelogSeenStore(userDefaults: defaults)
        store.lastSeenBuild = 49
        store.lastSeenBuild = nil
        #expect(store.lastSeenBuild == nil)
    }

    // Build 0 is the sentinel for "not set" - if somehow a 0 is stored, it must
    // be read back as nil rather than 0.
    @Test func storedZeroIsReadAsNil() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "lastSeenChangelogBuild")
        let store = UserDefaultsChangelogSeenStore(userDefaults: defaults)
        #expect(store.lastSeenBuild == nil)
    }
}

// MARK: - UserDefaultsUpdateCheckStateStore

struct UpdateCheckStateStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - lastCheckedAt

    @Test func lastCheckedAtDefaultIsNil() {
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: makeDefaults())
        #expect(store.lastCheckedAt == nil)
    }

    // Dates are stored as TimeInterval (seconds since epoch), so the round-trip
    // must preserve sub-second precision for the throttle window to be accurate.
    @Test func lastCheckedAtRoundTrips() {
        let defaults = makeDefaults()
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        let date = Date(timeIntervalSince1970: 1_000_000.5)
        store.lastCheckedAt = date
        #expect(store.lastCheckedAt == date)
    }

    @Test func lastCheckedAtPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        let date = Date(timeIntervalSince1970: 1_234_567)
        store1.lastCheckedAt = date

        let store2 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store2.lastCheckedAt == date)
    }

    @Test func settingLastCheckedAtToNilClearsIt() {
        let defaults = makeDefaults()
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        store.lastCheckedAt = Date()
        store.lastCheckedAt = nil
        #expect(store.lastCheckedAt == nil)
    }

    // MARK: - dismissedBuild

    @Test func dismissedBuildDefaultIsNil() {
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: makeDefaults())
        #expect(store.dismissedBuild == nil)
    }

    @Test func dismissedBuildRoundTrips() {
        let defaults = makeDefaults()
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        store.dismissedBuild = 49
        #expect(store.dismissedBuild == 49)
    }

    @Test func dismissedBuildPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        store1.dismissedBuild = 49

        let store2 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store2.dismissedBuild == 49)
    }

    // Storing 0 for dismissedBuild must come back as nil because 0 is the
    // internal sentinel for "not set" - dismissing build 0 is not a real case.
    @Test func dismissedBuildZeroIsReadAsNil() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "dismissedUpdateBuild")
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store.dismissedBuild == nil)
    }

    // MARK: - cachedPublishedBuild

    @Test func cachedPublishedBuildDefaultIsNil() {
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: makeDefaults())
        #expect(store.cachedPublishedBuild == nil)
    }

    @Test func cachedPublishedBuildRoundTrips() {
        let defaults = makeDefaults()
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        store.cachedPublishedBuild = 49
        #expect(store.cachedPublishedBuild == 49)
    }

    @Test func cachedPublishedBuildPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store1 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        store1.cachedPublishedBuild = 49

        let store2 = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store2.cachedPublishedBuild == 49)
    }

    @Test func cachedPublishedBuildZeroIsReadAsNil() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "cachedRemoteBuild")
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store.cachedPublishedBuild == nil)
    }

    // MARK: - forcesCheck

    // forcesCheck defaults to false. Only a developer explicitly setting the
    // UserDefaults flag should enable it.
    @Test func forcesCheckDefaultIsFalse() {
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: makeDefaults())
        #expect(store.forcesCheck == false)
    }

    @Test func forcesCheckReflectsUserDefaultsFlag() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "forceUpdateCheck")
        let store = UserDefaultsUpdateCheckStateStore(userDefaults: defaults)
        #expect(store.forcesCheck == true)
    }
}
