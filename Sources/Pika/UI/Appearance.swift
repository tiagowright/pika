import AppKit

/// Turns `[appearance] theme` into the colours on screen (SETTINGS.md
/// §3.1). In `auto` it follows macOS, repainting live when the system
/// switches between Light and Dark. It also sets `NSApp.appearance`, so
/// Pika's own windows (settings, onboarding) follow the same choice, and
/// swaps the app icon to match.
///
/// Main thread only.
final class Appearance {
    static let shared = Appearance()

    private(set) var theme: Theme = .catppuccinMocha
    private var mode: ThemeMode = .auto
    private var observers: [(Theme) -> Void] = []
    private var systemObservation: NSKeyValueObservation?

    private init() {}

    func start() {
        guard systemObservation == nil else { return }
        setMode(ConfigStore.shared.config.themeMode)
        ConfigStore.shared.observe { [weak self] old, new in
            guard old.themeMode != new.themeMode else { return }
            self?.setMode(new.themeMode)
        }
        // `effectiveAppearance` is KVO-observable and changes when the
        // user flips Light/Dark (or Auto flips at sunset) while
        // `NSApp.appearance` is nil.
        systemObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.recompute() }
        }
    }

    func observe(_ handler: @escaping (Theme) -> Void) {
        observers.append(handler)
    }

    private func setMode(_ newMode: ThemeMode) {
        mode = newMode
        switch newMode {
        case .auto: NSApp.appearance = nil
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        }
        recompute()
    }

    private func recompute() {
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let newTheme = Theme.resolve(mode, systemIsDark: systemIsDark)
        guard newTheme != theme else { return }
        theme = newTheme
        PikaArt.applyAppIcon(for: newTheme)
        observers.forEach { $0(newTheme) }
    }
}
