import Foundation
import os

/// Measures the app-controlled portion of dictation latency: from the hotkey release
/// TapTalk observes, to the paste event it posts.
///
/// Deliberately excludes what the app cannot see — HID delivery before the event tap fires,
/// and the target application's own handling after Cmd-V is posted. Those are real but not
/// ours to optimize, and including them would need a second process to observe.
///
/// Emits one line per dictation. Read them with:
///   log stream --predicate 'subsystem == "talk.tap.app" && category == "latency"'
struct LatencyTrace {
    private static let logger = Logger(subsystem: "talk.tap.app", category: "latency")

    private let start: ContinuousClock.Instant
    private var last: ContinuousClock.Instant
    private var stages: [(name: String, ms: Double)] = []

    init() {
        let now = ContinuousClock.now
        start = now
        last = now
    }

    /// Records the time since the previous mark.
    mutating func mark(_ name: String) {
        let now = ContinuousClock.now
        stages.append((name, Self.milliseconds(from: last, to: now)))
        last = now
    }

    /// Records a final mark and emits the line. `total` is the figure that matters.
    func finish(_ name: String) {
        var trace = self
        trace.mark(name)
        let total = Self.milliseconds(from: start, to: ContinuousClock.now)
        let breakdown = trace.stages
            .map { "\($0.name)=\(String(format: "%.0f", $0.ms))" }
            .joined(separator: " ")
        Self.logger.info("keyup→paste total=\(String(format: "%.0f", total))ms \(breakdown)")
    }

    private static func milliseconds(
        from a: ContinuousClock.Instant, to b: ContinuousClock.Instant
    ) -> Double {
        let d = a.duration(to: b)
        return Double(d.components.seconds) * 1000
            + Double(d.components.attoseconds) / 1_000_000_000_000_000
    }
}
