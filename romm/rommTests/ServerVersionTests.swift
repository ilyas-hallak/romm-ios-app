//
//  ServerVersionTests.swift
//  rommTests
//

import Testing
@testable import romm

struct ServerVersionTests {
    @Test func equalVersionsCompareEqual() {
        #expect(ServerVersion.compare("4.8.0", "4.8.0") == 0)
    }

    @Test func lowerVersionComparesBelow() {
        #expect(ServerVersion.compare("4.7.0", "4.8.0") < 0)
    }

    @Test func higherVersionComparesAbove() {
        #expect(ServerVersion.compare("4.9.0", "4.8.0") > 0)
    }

    @Test func developmentComparesAboveEveryReleaseOnBothSides() {
        #expect(ServerVersion.compare("development", "99.0.0") > 0)
        #expect(ServerVersion.compare("99.0.0", "development") < 0)
        // The first argument wins the check outright, so two "development"
        // builds compare as "above", not equal. A quirk, but the one every
        // caller already relies on, so the dedup keeps it unchanged.
        #expect(ServerVersion.compare("development", "development") > 0)
    }

    @Test func preReleaseSuffixIsIgnored() {
        #expect(ServerVersion.compare("4.8.0-rc1", "4.8.0") == 0)
    }

    @Test func missingComponentsCountAsZero() {
        #expect(ServerVersion.compare("4.8", "4.8.0") == 0)
    }
}
