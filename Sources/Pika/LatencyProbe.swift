import AppKit

/// Opt-in timing behind the README's latency table (bench/latency.sh).
/// Off, and free, unless `PIKA_LATENCY_LOG` names a file.
///
/// A sample runs from the triggering key event's timestamp — stamped when
/// the event was created, before the window server routed it to us — to
/// the end of the run-loop pass that handled it. By then AppKit has drawn
/// and Core Animation has committed the frame to the window server, which
/// shows it at the next display refresh. Each sample appends `kind<TAB>ms`.
enum LatencyProbe {
    enum Kind: String { case hotkey, keystroke, enter }

    private static let log: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["PIKA_LATENCY_LOG"], !path.isEmpty else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()
    private static var pending: (kind: Kind, start: TimeInterval)?
    private static var observer: CFRunLoopObserver?

    /// `eventTime` is seconds since boot, the clock of `NSEvent.timestamp`
    /// and Carbon's `GetEventTime`.
    static func begin(_ kind: Kind, eventTime: TimeInterval) {
        guard log != nil else { return }
        pending = (kind, eventTime)
        installObserverIfNeeded()
    }

    private static func installObserverIfNeeded() {
        guard observer == nil else { return }
        // Ordered last, after AppKit's display pass and Core Animation's
        // commit, which also run just before the main run loop sleeps.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            guard let sample = pending else { return }
            pending = nil
            let ms = (ProcessInfo.processInfo.systemUptime - sample.start) * 1000
            log?.write(Data("\(sample.kind.rawValue)\t\(String(format: "%.3f", ms))\n".utf8))
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }
}
