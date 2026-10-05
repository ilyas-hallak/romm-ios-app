import Testing
import Foundation
@testable import romm

/// The pure rules every battery sync path routes through: blank detection,
/// the GBA RTC footer trim, and picking/applying the newest download
/// candidate. See issue #208.
struct BatterySaveRulesTests {

    // MARK: - BatterySaveBlank

    @Test func allOxFFIsBlank() {
        #expect(BatterySaveBlank.isBlank(Data(repeating: 0xFF, count: 0x10000)))
    }

    @Test func allZeroIsBlank() {
        #expect(BatterySaveBlank.isBlank(Data(repeating: 0x00, count: 0x10000)))
    }

    @Test func emptyIsBlank() {
        #expect(BatterySaveBlank.isBlank(Data()))
    }

    @Test func mixedBytesIsNotBlank() {
        var data = Data(repeating: 0xFF, count: 0x10000)
        data[42] = 0x01
        #expect(!BatterySaveBlank.isBlank(data))
    }

    // MARK: - GBABatteryFooter

    @Test func trimsA16ByteFooterOffAValidFlashSize() {
        let data = Data(repeating: 0xAB, count: 0x20000 + 16)
        let trimmed = GBABatteryFooter.trimmingRTCFooter(from: data)
        #expect(trimmed.count == 0x20000)
    }

    @Test func leavesAnExactValidSizeUnchanged() {
        let data = Data(repeating: 0xAB, count: 0x20000)
        let trimmed = GBABatteryFooter.trimmingRTCFooter(from: data)
        #expect(trimmed.count == 0x20000)
    }

    @Test func leavesAnOddSizeUnchanged() {
        let data = Data(repeating: 0xAB, count: 12345)
        let trimmed = GBABatteryFooter.trimmingRTCFooter(from: data)
        #expect(trimmed.count == 12345)
    }

    // MARK: - BatteryDownloadPicker

    private struct Candidate {
        let name: String
        let updatedAt: Date?
    }

    @Test func pickNewestWinsByTimestamp() {
        let older = Candidate(name: "old", updatedAt: Date(timeIntervalSince1970: 100))
        let newer = Candidate(name: "new", updatedAt: Date(timeIntervalSince1970: 200))
        let picked = BatteryDownloadPicker.pickNewest([older, newer], updatedAt: \.updatedAt)
        #expect(picked?.name == "new")
    }

    @Test func pickNewestPrefersAnyTimestampOverNone() {
        let noTimestamp = Candidate(name: "none", updatedAt: nil)
        let timestamped = Candidate(name: "some", updatedAt: Date(timeIntervalSince1970: 1))
        let picked = BatteryDownloadPicker.pickNewest([noTimestamp, timestamped], updatedAt: \.updatedAt)
        #expect(picked?.name == "some")
    }

    @Test func pickNewestOnEmptyIsNil() {
        let picked = BatteryDownloadPicker.pickNewest([Candidate](), updatedAt: \.updatedAt)
        #expect(picked == nil)
    }

    // MARK: - BatteryDownloadDecision

    @Test func missingLocalBatteryAlwaysApplies() {
        let applies = BatteryDownloadDecision.shouldApply(
            candidateUpdatedAt: Date(timeIntervalSince1970: 1), localModifiedAt: nil, localIsBlank: true
        )
        #expect(applies)
    }

    @Test func blankLocalBatteryAlwaysApplies() {
        let applies = BatteryDownloadDecision.shouldApply(
            candidateUpdatedAt: Date(timeIntervalSince1970: 1),
            localModifiedAt: Date(timeIntervalSince1970: 999_999),
            localIsBlank: true
        )
        #expect(applies)
    }

    @Test func newerCandidateAppliesOverANonBlankLocalBattery() {
        let applies = BatteryDownloadDecision.shouldApply(
            candidateUpdatedAt: Date(timeIntervalSince1970: 200),
            localModifiedAt: Date(timeIntervalSince1970: 100),
            localIsBlank: false
        )
        #expect(applies)
    }

    @Test func olderCandidateDoesNotApplyOverANonBlankLocalBattery() {
        let applies = BatteryDownloadDecision.shouldApply(
            candidateUpdatedAt: Date(timeIntervalSince1970: 100),
            localModifiedAt: Date(timeIntervalSince1970: 200),
            localIsBlank: false
        )
        #expect(!applies)
    }

    @Test func candidateWithNoTimestampDoesNotApplyOverANonBlankLocalBattery() {
        let applies = BatteryDownloadDecision.shouldApply(
            candidateUpdatedAt: nil,
            localModifiedAt: Date(timeIntervalSince1970: 200),
            localIsBlank: false
        )
        #expect(!applies)
    }
}
