import Testing
@testable import romm

struct RetroAchievementsProgressionTests {
    private func makeAchievement(id: String, badgeId: String?) -> RetroAchievement {
        RetroAchievement(
            id: id,
            badgeId: badgeId,
            title: "Test Achievement",
            description: nil,
            points: 5,
            badgeURL: nil,
            lockedBadgeURL: nil,
            displayOrder: nil
        )
    }

    private func makeProgression(
        earned: [EarnedRetroAchievement]
    ) -> RetroAchievementsProgression {
        RetroAchievementsProgression(
            gameId: 7,
            awardedCount: earned.count,
            awardedHardcoreCount: nil,
            maximumCount: 10,
            earnedAchievements: earned
        )
    }

    /// The server keys unlocks by badge name, not by RetroAchievements ID.
    @Test func findsAnEarnedAchievementByBadgeIdentifier() {
        let unlock = EarnedRetroAchievement(
            id: "123456",
            earnedAt: "2026-08-29T10:00:00Z",
            earnedHardcoreAt: nil
        )
        let progression = makeProgression(earned: [unlock])

        #expect(progression.earnedAchievement(for: makeAchievement(id: "42", badgeId: "123456")) == unlock)
        #expect(progression.earnedAchievement(for: makeAchievement(id: "42", badgeId: "999999")) == nil)
    }

    /// The achievement's own ID must never be used as a fallback match, otherwise
    /// an unrelated unlock with the same numeric value would light up.
    @Test func doesNotMatchOnTheAchievementIdentifier() {
        let unlock = EarnedRetroAchievement(
            id: "42",
            earnedAt: "2026-08-29T10:00:00Z",
            earnedHardcoreAt: nil
        )
        let progression = makeProgression(earned: [unlock])

        #expect(progression.earnedAchievement(for: makeAchievement(id: "42", badgeId: "123456")) == nil)
    }

    /// RomM stores a missing badge as an empty string rather than as null.
    @Test func treatsMissingBadgeIdentifiersAsNotEarned() {
        let unlock = EarnedRetroAchievement(
            id: "",
            earnedAt: "2026-08-29T10:00:00Z",
            earnedHardcoreAt: nil
        )
        let progression = makeProgression(earned: [unlock])

        #expect(progression.earnedAchievement(for: makeAchievement(id: "42", badgeId: "")) == nil)
        #expect(progression.earnedAchievement(for: makeAchievement(id: "42", badgeId: nil)) == nil)
    }
}
