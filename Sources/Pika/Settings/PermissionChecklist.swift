import AppKit
import SwiftUI

/// Every permission and health check Pika depends on, each with its live
/// status, why it's needed, and one button that does the right thing for
/// the state it's in (SETTINGS.md §2.3). Shown in Settings → Permissions
/// and, in step 6, in onboarding.
struct PermissionChecklist: View {
    enum Item: String, CaseIterable {
        case accessibility, chrome, loginItem, hotkey
        var id: String { rawValue }
    }

    @Bindable var model: SettingsModel
    var items: [Item] = Item.allCases
    /// Onboarding offers "Skip" on optional rows that aren't done yet.
    var allowSkip = false
    /// Where a hotkey "Change…" button should take the user.
    var onChangeHotkey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Divider() }
                switch item {
                case .accessibility: AccessibilityRow(model: model)
                case .chrome: ChromeRow(model: model, allowSkip: allowSkip)
                case .loginItem: LoginItemRow(model: model, allowSkip: allowSkip)
                case .hotkey: HotkeyRow(model: model, onChange: onChangeHotkey)
                }
            }
        }
    }
}

// MARK: - Row scaffolding

enum RowStatus {
    case good, bad, attention, neutral

    var symbol: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .bad: return "xmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .neutral: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .good: return .green
        case .bad: return .red
        case .attention: return .orange
        case .neutral: return .secondary
        }
    }
}

struct ChecklistRow<Actions: View, Detail: View>: View {
    let title: String
    let required: Bool
    let why: String
    let status: RowStatus
    let statusText: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(required ? "required" : "optional")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .foregroundStyle(.secondary)
                }
                Text(why).font(.callout).foregroundStyle(.secondary)
                // Status in words too, never colour alone (SETTINGS.md §2.3.6).
                Text(statusText).font(.callout).foregroundStyle(status == .good ? Color.secondary : status.color)
                detail
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) { actions }
                .controlSize(.regular)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(required ? "required" : "optional"): \(statusText)")
    }
}

extension ChecklistRow where Detail == EmptyView {
    init(title: String, required: Bool, why: String, status: RowStatus, statusText: String, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, required: required, why: why, status: status, statusText: statusText, actions: actions, detail: { EmptyView() })
    }
}

/// The System Settings path, spelled out, for when the deep link lands
/// somewhere slightly different.
private struct SettingsPath: View {
    let path: String
    var body: some View {
        Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
}

// MARK: - Accessibility

private struct AccessibilityRow: View {
    @Bindable var model: SettingsModel

    private static let resetCommand = "tccutil reset Accessibility io.github.tiagowright.pika"

    var body: some View {
        ChecklistRow(
            title: "Accessibility",
            required: true,
            why: "Reads the title of each open window and raises the one you pick.",
            status: model.accessibility ? .good : .bad,
            statusText: model.accessibility ? "Granted" : "Not granted — Pika can't list or switch windows"
        ) {
            if model.accessibility {
                Button("Open in System Settings") { StatusItemController.openSystemSettings(SystemSettingsPane.accessibility) }
            } else {
                Button("Open System Settings…") { model.requestAccessibility() }
                .buttonStyle(.borderedProminent)
            }
        } detail: {
            if !model.accessibility {
                SettingsPath(path: "Privacy & Security → Accessibility → turn on Pika")
                if model.showAccessibilityTroubleshooting {
                    troubleshooting
                }
            }
        }
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still not granted? Usually one of these:").font(.callout.weight(.semibold))
            Text("• Pika isn't in the list: click + and choose Pika in Applications, or drag Pika.app into the list.")
            Text("• Pika is in the list and on, but nothing changes: turn it off and on again.")
            Text("• The switch won't stay on, or Pika is listed twice: the old grant is stale (common after rebuilding Pika). Reset it in Terminal, then quit and reopen Pika:")
            HStack {
                Text(Self.resetCommand)
                    .font(.custom(PikaFont.family, size: 11))
                    .textSelection(.enabled)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.resetCommand, forType: .string)
                }
            }
        }
        .font(.callout)
        .padding(.top, 6)
    }
}

// MARK: - Chrome

private struct ChromeRow: View {
    @Bindable var model: SettingsModel
    var allowSkip = false

    var body: some View {
        let (status, text) = model.isSkipped(.chrome) && !model.config.chromeTabs
            ? (RowStatus.neutral, "Skipped — Chrome is listed by window. Turn on any time in Settings → Sources.")
            : describe()
        ChecklistRow(
            title: "Chrome tabs (Automation)",
            required: false,
            why: "Lists each Chrome tab, not just each Chrome window.",
            status: status,
            statusText: text
        ) {
            actions
        } detail: {
            if model.chrome.grant == .denied {
                SettingsPath(path: "Privacy & Security → Automation → Pika → Google Chrome")
            }
        }
    }

    private func describe() -> (RowStatus, String) {
        if !model.config.chromeTabs {
            return (.neutral, "Off — Chrome is listed by window (Sources → Chrome tabs)")
        }
        switch model.chrome {
        case .granted: return (.good, "Granted")
        case .denied: return (.attention, "Denied — Chrome is listed by window")
        case .notAsked: return (.neutral, "Not asked yet")
        case .chromeNotInstalled: return (.neutral, "Google Chrome isn't installed")
        case .chromeNotRunning(let lastKnown):
            switch lastKnown {
            case .granted: return (.good, "Granted")
            case .denied: return (.attention, "Denied — Chrome is listed by window")
            case .notAsked, nil: return (.neutral, "Chrome isn't open — Pika will ask the first time it sees Chrome")
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if !model.config.chromeTabs {
            Button("Turn On") { model.set("sources", "chrome_tabs", .bool(true)) }
        } else {
            chromeActions
            if allowSkip, model.chrome.grant != .granted {
                Button("Skip") { model.skip(.chrome) }.buttonStyle(.link)
            }
        }
    }

    @ViewBuilder private var chromeActions: some View {
        switch model.chrome.grant {
        case .denied:
            Button("Open System Settings…") { StatusItemController.openSystemSettings(SystemSettingsPane.automation) }
                .buttonStyle(.borderedProminent)
        case .notAsked, nil:
            if case .notAsked = model.chrome {
                Button("Allow…") { model.requestChromeAccess() }
                    .buttonStyle(.borderedProminent)
            } else if case .chromeNotRunning = model.chrome {
                Button("Open Chrome") { model.openChrome() }
            }
        case .granted:
            EmptyView()
        }
    }
}

// MARK: - Launch at login

private struct LoginItemRow: View {
    @Bindable var model: SettingsModel
    var allowSkip = false

    var body: some View {
        let skipped = model.isSkipped(.loginItem) && model.loginItem == .off
        let (status, text): (RowStatus, String) = switch model.loginItem {
        case .on: (.good, "On")
        case .off where skipped: (.neutral, "Skipped — turn on any time in Settings → General")
        case .off: (.neutral, "Off — start Pika yourself after logging in")
        case .needsApproval: (.attention, "Waiting for your approval in System Settings → Login Items")
        case .unavailable: (.neutral, "Only available when Pika runs from /Applications")
        }
        ChecklistRow(
            title: "Start at login",
            required: false,
            why: "Keeps the hotkey working after a restart.",
            status: status,
            statusText: text
        ) {
            switch model.loginItem {
            case .on: Button("Turn Off") { model.setLaunchAtLogin(false) }
            case .off:
                Button("Turn On") { model.setLaunchAtLogin(true) }
                    .buttonStyle(.borderedProminent)
                if allowSkip, !skipped {
                    Button("Skip") { model.skip(.loginItem) }.buttonStyle(.link)
                }
            case .needsApproval:
                Button("Open Login Items…") { StatusItemController.openSystemSettings(SystemSettingsPane.loginItems) }
                    .buttonStyle(.borderedProminent)
            case .unavailable: EmptyView()
            }
        }
    }
}

// MARK: - Hotkey

private struct HotkeyRow: View {
    @Bindable var model: SettingsModel
    var onChange: () -> Void

    var body: some View {
        let hotkey = model.config.hotkey
        let (status, text): (RowStatus, String) = switch model.hotkeyHealth {
        case .ok: (.good, "\(hotkey) opens Pika")
        case .notRegisteredYet: (.neutral, "Turns on once Accessibility is granted")
        case .takenByApp: (.bad, "Another app already uses \(hotkey), so it does nothing")
        case .shadowedBySystem(let name): (.bad, "macOS uses \(hotkey) for “\(name)” and gets it first")
        }
        ChecklistRow(
            title: "Hotkey",
            required: true,
            why: "The shortcut that opens the switcher.",
            status: status,
            statusText: text
        ) {
            if case .shadowedBySystem = model.hotkeyHealth {
                Button("Open Keyboard Shortcuts…") { StatusItemController.openSystemSettings(SystemSettingsPane.keyboard) }
            }
            if model.hotkeyHealth.isProblem {
                Button("Change Hotkey…", action: onChange).buttonStyle(.borderedProminent)
            }
        }
    }
}
