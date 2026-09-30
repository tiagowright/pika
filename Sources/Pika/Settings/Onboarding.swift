import AppKit
import Observation
import SwiftUI

/// First-run setup (SETTINGS.md §2.2 option 2): Welcome → the permission
/// checklist → try the hotkey. Runs when state.json's onboarding version is
/// older than `Onboarding.version`, or from Settings → Permissions → Run
/// Setup Again. Shares SettingsModel with the settings window.
enum Onboarding {
    /// Bump when a release needs something new from the user.
    static let version = 1

    static var isDue: Bool { StateStore.shared.state.onboardingVersion < version }

    static func markComplete() {
        StateStore.shared.update {
            $0.onboardingVersion = version
            $0.onboardingCompletedAt = Date()
        }
    }
}

@Observable
final class OnboardingFlow {
    enum Page: Int, CaseIterable { case welcome, checklist, tryIt }
    var page: Page = .welcome
}

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    let flow = OnboardingFlow()
    private var finished = false

    var isWaitingForHotkey: Bool { window?.isVisible == true && flow.page == .tryIt }
    var isOpen: Bool { window?.isVisible == true || window?.isMiniaturized == true }

    init(model: SettingsModel) {
        PikaFont.registerBundled()
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Set Up Pika"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model, flow: flow, onFinish: { [weak self] in self?.finish() }))
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Always from the start (SHIPPING Q6): the checklist shows what's
    /// already done, so nothing is repeated needlessly.
    /// `resetting: false` just brings an open Setup back to the front.
    func show(resetting: Bool = true) {
        if resetting {
            finished = false
            flow.page = .welcome
        }
        PermissionCenter.shared.refresh()
        model.sync()
        guard let window else { return }
        window.center()
        AppPresence.windowOpened(window)
        showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    /// Done, or the hotkey was pressed on the last page.
    func finish() {
        finished = true
        Onboarding.markComplete()
        close()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        PermissionCenter.shared.refresh()
        model.sync()
    }

    /// Closing early still counts as done once Pika can work; otherwise it
    /// comes back next launch, and the menu bar badge points the way in the
    /// meantime (SETTINGS.md §2.4.5).
    func windowWillClose(_ notification: Notification) {
        model.stopRecordingHotkey()
        if !finished, model.accessibility { Onboarding.markComplete() }
        if let window { AppPresence.windowClosed(window) }
    }
}

// MARK: - Views

struct OnboardingView: View {
    @Bindable var model: SettingsModel
    @Bindable var flow: OnboardingFlow
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("\(flow.page.rawValue + 1) of \(OnboardingFlow.Page.allCases.count)")
                    .font(.custom(PikaFont.family, size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            Group {
                switch flow.page {
                case .welcome: WelcomePage(model: model)
                case .checklist: ChecklistPage(model: model)
                case .tryIt: TryItPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 640, height: 600)
        .tint(Color(nsColor: model.theme.accent))
        .toggleStyle(.switch)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if flow.page != .welcome {
                Button("Back") { flow.page = OnboardingFlow.Page(rawValue: flow.page.rawValue - 1)! }
            }
            Spacer()
            switch flow.page {
            case .welcome:
                Button("Later") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { flow.page = .checklist }
                    .keyboardShortcut(.defaultAction)
            case .checklist:
                if !model.requiredItemsDone {
                    Text(model.accessibility ? "Fix the hotkey to continue" : "Grant Accessibility to continue")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button("Continue") { flow.page = .tryIt }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.requiredItemsDone)
            case .tryIt:
                Button("Done") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct WelcomePage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                .padding(.top, 12)
            Text("Welcome to Pika").font(.largeTitle.weight(.semibold))
            Text("Switch to any window by name: press \(Text(model.config.hotkey).font(.custom(PikaFont.family, size: 15))), type a few letters, press Enter.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                bullet("lock.shield", "Pika needs **Accessibility** to read window titles and raise the window you pick.")
                bullet("square.stack", "Optionally, **Automation for Chrome** to list individual tabs.")
                bullet("eye.slash", "It never asks for Screen Recording or Input Monitoring.")
                bullet("network.slash", "Nothing it reads leaves this Mac. No network, no telemetry.")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternarySystemFill)))
            .padding(.top, 8)
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChecklistPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("A few things to set up").font(.title2.weight(.semibold))
                Text("Optional rows can be skipped and turned on later in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                PermissionChecklist(model: model, allowSkip: true) {}
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
                if model.hotkeyHealth.isProblem {
                    HStack {
                        Text("Pick a different hotkey:")
                        HotkeyRecorder(model: model)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct TryItPage: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 28) {
            Text("Try it").font(.largeTitle.weight(.semibold)).padding(.top, 48)
            HStack(spacing: 8) {
                ForEach(Array(model.config.hotkey.split(separator: "+").enumerated()), id: \.offset) { index, key in
                    if index > 0 { Text("+").foregroundStyle(.secondary) }
                    Text(String(key))
                        .font(.custom(PikaFont.family, size: 22).weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternarySystemFill)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
                }
            }
            Text("Type a few letters of a window's name, then press Enter.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: PikaGlyph.menuBarImage(badged: false)).renderingMode(.template)
                    .foregroundStyle(.secondary)
                Text("To get back to Settings, click the pika head in the menu bar, or open Pika from Spotlight.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .quaternarySystemFill)))
            .padding(.top, 12)
        }
    }
}
