import SwiftUI

/// In-game control for the screen placement while a physical controller is
/// attached: a height slider plus a reset for the drag position. The vertical
/// position itself is set by dragging the game directly, so this only carries a
/// hint for that. Callers show it only in controller mode (a controller is
/// connected); otherwise the placement has no effect.
struct EmulatorScreenControls: View {
    let preference: PEmulatorScreenPositionPreference
    /// Called after a change so the renderer can re-apply the placement live.
    var onChange: () -> Void = {}

    @SwiftUI.State private var heightFraction: Double

    init(preference: PEmulatorScreenPositionPreference, onChange: @escaping () -> Void = {}) {
        self.preference = preference
        self.onChange = onChange
        self._heightFraction = SwiftUI.State(initialValue: preference.heightFraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Screen size", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(Int((heightFraction * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .monospacedDigit()
            }
            Slider(value: $heightFraction, in: 0.3...1.0, step: 0.05)
                .onChange(of: heightFraction) { _, newValue in
                    preference.heightFraction = newValue
                    onChange()
                }
            HStack(spacing: 8) {
                Text("Drag the screen to move it.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button("Reset position") {
                    preference.verticalOffset = 0.5
                    onChange()
                }
                .font(.caption)
            }
        }
    }
}
