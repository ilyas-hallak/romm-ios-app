import Foundation
import QuartzCore

#if DEBUG
/// Measures the extra delay AirPlay adds, using the player as the feedback
/// channel. There is no API for this: iOS never tells an app when a frame
/// actually appeared on the Apple TV, and anything drawn on the TV arrives with
/// the very delay we are trying to measure, so it cannot reveal it.
///
/// The trick is to cancel out human reaction time instead of fighting it. The
/// picture flashes white and the player taps as soon as they see it, twice over:
///
///   looking at the phone → reaction + local latency
///   looking at the TV    → reaction + local latency + AirPlay
///
/// The difference between the two rounds is the AirPlay share, because reaction
/// time appears in both and drops out. Reaction time scatters by a few tens of
/// milliseconds, so several samples per round are taken and the median is used,
/// which shrugs off the odd missed flash.
@MainActor
final class LatencyProbe: ObservableObject {

    enum Phase: Equatable {
        case idle
        case phone(done: Int)
        case tv(done: Int)
        case result(phoneMs: Double, tvMs: Double)
    }

    /// Ten rather than a handful: reaction time scatters by a few tens of
    /// milliseconds, which is the same order as the gains we want to detect in
    /// the phone-only round, so the median needs enough samples to settle.
    static let samplesPerRound = 10

    @Published private(set) var phase: Phase = .idle

    /// Set while a flash is awaiting its tap, so a stray tap between flashes is
    /// ignored instead of being recorded as an absurdly long reaction.
    private var flashAt: CFTimeInterval?
    private var phoneSamples: [Double] = []
    private var tvSamples: [Double] = []

    var isRunning: Bool {
        switch phase {
        case .idle, .result: return false
        case .phone, .tv: return true
        }
    }

    /// Instruction shown to the player, phrased so it is clear which screen to
    /// watch, since watching the wrong one silently ruins the measurement.
    var instruction: String {
        switch phase {
        case .idle:
            return ""
        case .phone(let done):
            return "Watch THIS screen. Tap the moment it flashes white. (\(done)/\(Self.samplesPerRound))"
        case .tv(let done):
            return "Now watch the TV. Tap here the moment the TV flashes. (\(done)/\(Self.samplesPerRound))"
        case .result(let phoneMs, let tvMs):
            let delta = max(0, tvMs - phoneMs)
            return String(
                format: "Phone %.0f ms, TV %.0f ms.\nAirPlay adds about %.0f ms.",
                phoneMs, tvMs, delta
            )
        }
    }

    func start() {
        phoneSamples.removeAll()
        tvSamples.removeAll()
        flashAt = nil
        phase = .phone(done: 0)
    }

    func cancel() {
        flashAt = nil
        phase = .idle
    }

    /// Called from the render path the instant the white frame is pushed out.
    func flashDidShow() {
        guard isRunning else { return }
        flashAt = CACurrentMediaTime()
    }

    func tapped() {
        guard isRunning, let shownAt = flashAt else { return }
        let elapsedMs = (CACurrentMediaTime() - shownAt) * 1000
        flashAt = nil
        // A plausible reaction is a good bit above zero and well under a second.
        // Outside that the player either mistimed it or tapped at random, and
        // keeping it would poison the median.
        guard elapsedMs > 60, elapsedMs < 1200 else { return }

        switch phase {
        case .phone:
            phoneSamples.append(elapsedMs)
            phase = phoneSamples.count >= Self.samplesPerRound
                ? .tv(done: 0)
                : .phone(done: phoneSamples.count)
        case .tv:
            tvSamples.append(elapsedMs)
            if tvSamples.count >= Self.samplesPerRound {
                phase = .result(phoneMs: median(phoneSamples), tvMs: median(tvSamples))
            } else {
                phase = .tv(done: tvSamples.count)
            }
        case .idle, .result:
            break
        }
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}
#endif
