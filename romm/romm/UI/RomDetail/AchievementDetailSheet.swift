import SwiftUI

struct AchievementDetail: Identifiable {
    let achievement: RetroAchievement
    let earnedAchievement: EarnedRetroAchievement?

    var id: String { achievement.id }
}

struct AchievementDetailSheet: View {
    let detail: AchievementDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(detail.achievement.title)
                .font(.title2)
                .fontWeight(.bold)

            if let description = detail.achievement.description, !description.isEmpty {
                Text(description)
            }

            if let points = detail.achievement.points {
                Label("\(points) points", systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }

            if let earnedAchievement = detail.earnedAchievement {
                Label(
                    earnedAchievement.earnedHardcoreAt == nil ? "Unlocked" : "Unlocked in hardcore mode",
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(.green)

                if let date = earnedAchievement.earnedDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Locked", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
