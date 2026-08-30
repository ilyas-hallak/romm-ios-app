import Testing
@testable import romm

struct RetroAchievementsProgressionTests {
    @Test func findsAnEarnedAchievementByIdentifier() {
        let achievement = EarnedRetroAchievement(
            id: "42",
            earnedAt: "2026-08-29T10:00:00Z",
            earnedHardcoreAt: nil
        )
        let progression = RetroAchievementsProgression(
            gameId: 7,
            awardedCount: 1,
            maximumCount: 10,
            earnedAchievements: [achievement]
        )

        #expect(progression.earnedAchievement(id: "42") == achievement)
        #expect(progression.earnedAchievement(id: "99") == nil)
    }
}
