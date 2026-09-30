// Drives a running, instrumented Pika with synthetic key events and
// summarizes what its LatencyProbe logged. Run through bench/latency.sh,
// which launches Pika with the probe on.
//
// Each round: hotkey → type 4 letters → 4 backspaces → Enter. The empty
// query leaves the previous window on top, so Enter flips between the same
// two windows every round instead of wandering across Spaces.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let rounds = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: driver <log-path> <rounds> [warmup]\n".utf8))
    exit(2)
}
let logPath = args[1]
let warmup = args.count > 3 ? Int(args[3]) ?? 5 : 5

guard CGPreflightPostEventAccess() || CGRequestPostEventAccess() else {
    FileHandle.standardError.write(Data("""
        This terminal can't post key events. Grant it Accessibility in
        System Settings → Privacy & Security → Accessibility, then rerun.\n
        """.utf8))
    exit(1)
}

let source = CGEventSource(stateID: .hidSystemState)
let letters: [CGKeyCode] = [14, 17, 0, 31, 34, 45, 1, 15, 4, 37] // e t a o i n s r h l

func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)!
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}

func pause(_ ms: Int) { usleep(useconds_t(ms * 1000)) }
func jitter(_ ms: Int) -> Int { ms + Int.random(in: -ms / 4 ... ms / 4) }

func round() {
    press(49, flags: .maskControl) // ctrl+space
    pause(jitter(200))
    for _ in 0..<4 { press(letters.randomElement()!); pause(jitter(90)) }
    for _ in 0..<4 { press(51); pause(jitter(90)) } // backspace
    press(36) // Enter
    pause(jitter(400))
}

print("Warming up (\(warmup) rounds)…")
for _ in 0..<warmup { round() }
pause(300)
// Pika holds the log open, so skip the warm-up lines rather than truncate.
func logLines() -> [Substring] {
    ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "").split(separator: "\n")
}
let warmupLines = logLines().count
guard warmupLines > 0 else {
    FileHandle.standardError.write(Data("Pika logged nothing during warm-up — is the probe build installed, and did the hotkey open it?\n".utf8))
    exit(1)
}

let start = Date()
for i in 1...rounds {
    round()
    if i % 25 == 0 { print("  \(i)/\(rounds) rounds, \(Int(Date().timeIntervalSince(start)))s") }
}
pause(300)

// MARK: - Summary

var samples: [String: [Double]] = [:]
for line in logLines().dropFirst(warmupLines) {
    let parts = line.split(separator: "\t")
    guard parts.count == 2, let ms = Double(parts[1]) else { continue }
    samples[String(parts[0]), default: []].append(ms)
}

/// Nearest-rank percentile.
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    sorted[max(0, Int((p / 100 * Double(sorted.count)).rounded(.up)) - 1)]
}
func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

print("\n| Interaction | n | Mean | p50 | p90 | p99 | Max |")
print("|---|---:|---:|---:|---:|---:|---:|")
for (kind, label) in [("hotkey", "Hotkey → visible switcher"),
                      ("keystroke", "Keystroke → updated results"),
                      ("enter", "Enter → switcher dismissed")] {
    guard let values = samples[kind]?.sorted(), !values.isEmpty else {
        print("| \(label) | 0 | – | – | – | – | – |"); continue
    }
    let mean = values.reduce(0, +) / Double(values.count)
    print("| \(label) | \(values.count) | \(fmt(mean)) | \(fmt(percentile(values, 50))) | \(fmt(percentile(values, 90))) | \(fmt(percentile(values, 99))) | \(fmt(values.last!)) |")
}
