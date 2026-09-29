import AppKit
import SwiftUI

/// The settings window: a sidebar of panes, each a native form. Native
/// controls, with Pika's Catppuccin accent and JetBrains Mono wherever a
/// config.toml key or the hotkey is shown (SETTINGS.md §1.3, option C).
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        // The sidebar is always shown: no collapse button, and the column
        // can't be dragged shut.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsModel.Pane.allCases, selection: $model.pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .badge(badgeCount(for: pane))
                    .tag(pane)
            }
            .frame(minWidth: 210)
            .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                if !model.issues.isEmpty {
                    ConfigIssuesBanner(issues: model.issues)
                }
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle(model.pane.title)
        }
        .tint(Color(nsColor: model.theme.accent))
        .toggleStyle(.switch)
        .alert("Couldn't save", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } })) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
    }

    /// Sidebar badge: how many things need the user on that pane.
    private func badgeCount(for pane: SettingsModel.Pane) -> Int {
        switch pane {
        case .permissions: return model.accessibility ? 0 : 1
        case .general: return model.hotkeyHealth.isProblem ? 1 : 0
        default: return 0
        }
    }

    @ViewBuilder private var pane: some View {
        switch model.pane {
        case .general: GeneralPane(model: model)
        case .permissions: PermissionsPane(model: model)
        case .appearance: AppearancePane(model: model)
        case .search: SearchPane(model: model)
        case .sources: SourcesPane(model: model)
        case .privacy: PrivacyPane(model: model)
        case .about: AboutPane()
        }
    }
}

// MARK: - Shared pieces

/// One setting: label, control, and its config.toml key — as a tooltip,
/// and spelled out while ⌥ is held (SETTINGS.md §1.1 principle 4).
struct SettingRow<Control: View>: View {
    @Bindable var model: SettingsModel
    let title: String
    var note: String? = nil
    let key: String
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                if model.showKeys {
                    Text(key).font(.custom(PikaFont.family, size: 11)).foregroundStyle(.tint)
                }
            }
        }
        .help("config.toml: \(key)")
    }
}

/// A slider that writes only when the drag ends, not on every tick. The
/// in-progress value lives in the model, keyed by config key.
struct CommitSlider: View {
    @Bindable var model: SettingsModel
    let key: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    let onCommit: (Double) -> Void

    private var draft: Double? { model.sliderDrafts[key] }

    var body: some View {
        HStack {
            // No `step:` — on macOS it draws a tick for every step. Snap instead.
            Slider(value: Binding(get: { draft ?? value }, set: { model.sliderDrafts[key] = ($0 / step).rounded() * step }), in: range) { editing in
                if !editing, let draft {
                    onCommit(draft)
                    model.sliderDrafts[key] = nil
                }
            }
            .frame(width: 200)
            Text(format(draft ?? value))
                .font(.custom(PikaFont.family, size: 12))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}

private struct PaneFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Saved to ~/.config/pika/config.toml · hold ⌥ to see each key")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open") { StatusItemController.openConfigFile() }
                .buttonStyle(.link).font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

private struct ConfigIssuesBanner: View {
    let issues: [ConfigIssue]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issues.contains { !$0.isNotice } ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(issues.contains { !$0.isNotice } ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(issues.prefix(4).enumerated()), id: \.offset) { _, issue in
                    Text(issue.description).font(.callout).textSelection(.enabled)
                }
                if issues.count > 4 {
                    Text("…and \(issues.count - 4) more").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Open config.toml") { StatusItemController.openConfigFile() }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingRow(model: model, title: "Hotkey", note: hotkeyNote, key: "hotkey") {
                        HotkeyRecorder(model: model)
                    }
                    if case .shadowedBySystem(let name) = model.hotkeyHealth {
                        HStack {
                            Label("macOS uses this for “\(name)” and gets it first.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Keyboard Shortcuts…") { StatusItemController.openSystemSettings(SystemSettingsPane.keyboard) }
                        }
                        .font(.callout)
                    }
                }
                Section {
                    LabeledContent("Start Pika at login") {
                        Toggle("", isOn: Binding(get: { model.loginItem == .on }, set: { model.setLaunchAtLogin($0) }))
                            .labelsHidden()
                            .disabled(model.loginItem == .unavailable)
                    }
                    .help("Managed by macOS (System Settings → General → Login Items), not config.toml")
                    if model.loginItem == .needsApproval {
                        Text("Waiting for approval in System Settings → General → Login Items.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            PaneFooter()
        }
    }

    private var hotkeyNote: String? {
        switch model.hotkeyHealth {
        case .ok: return "Working"
        case .notRegisteredYet: return "Turns on once Accessibility is granted"
        case .takenByApp: return "Another app already uses this — pick a different one"
        case .shadowedBySystem: return nil
        }
    }
}

private struct PermissionsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pika asks for as little as possible. It never uses Screen Recording or Input Monitoring, and nothing it reads leaves this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                // Only real macOS permissions here. Start at login and the
                // hotkey live in General; onboarding shows all four.
                PermissionChecklist(model: model, items: [.accessibility, .chrome]) { model.pane = .general }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            }
            .padding(20)
        }
    }
}

private struct AppearancePane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingRow(model: model, title: "Theme", key: "appearance.theme") {
                        Picker("", selection: Binding(get: { model.config.themeMode }, set: { model.set("appearance", "theme", .string($0.rawValue)) })) {
                            Text("Auto").tag(ThemeMode.auto)
                            Text("Dark").tag(ThemeMode.dark)
                            Text("Light").tag(ThemeMode.light)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    // The selected mode, even before the switch has repainted anything.
                    ThemePreview(theme: Theme.resolve(model.config.themeMode, systemIsDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua))
                }
                Section {
                    SettingRow(model: model, title: "Font size", key: "appearance.font_size") {
                        Stepper(value: Binding(get: { Double(model.config.fontSize) }, set: { model.set("appearance", "font_size", .double($0)) }), in: 9...24) {
                            Text("\(Int(model.config.fontSize)) pt").monospacedDigit()
                        }
                    }
                    SettingRow(model: model, title: "Panel width", key: "appearance.width") {
                        CommitSlider(model: model, key: "appearance.width", value: Double(model.config.panelWidth), range: 400...1600, step: 20, format: { "\(Int($0))" }) {
                            model.set("appearance", "width", .double($0))
                        }
                    }
                    SettingRow(model: model, title: "Rows shown", key: "appearance.max_rows") {
                        Stepper(value: Binding(get: { model.config.maxRows }, set: { model.set("appearance", "max_rows", .int($0)) }), in: 3...30) {
                            Text("\(model.config.maxRows)").monospacedDigit()
                        }
                    }
                    SettingRow(model: model, title: "App icons", key: "appearance.show_icons") {
                        Toggle("", isOn: Binding(get: { model.config.showIcons }, set: { model.set("appearance", "show_icons", .bool($0)) })).labelsHidden()
                    }
                    SettingRow(model: model, title: "Blinking cursor", key: "appearance.cursor.blink") {
                        Toggle("", isOn: Binding(get: { model.config.cursorBlink }, set: { model.set("appearance.cursor", "blink", .bool($0)) })).labelsHidden()
                    }
                }
            }
            .formStyle(.grouped)
            PaneFooter()
        }
    }
}

/// A two-row sample of the switcher in the theme currently in effect.
private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        let mono = Font.custom(PikaFont.family, size: 12)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("❯ ").foregroundStyle(Color(nsColor: theme.accent))
                Text("pi").foregroundStyle(Color(nsColor: theme.fg))
                Rectangle().fill(Color(nsColor: theme.accent).opacity(0.85)).frame(width: 7, height: 14)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(nsColor: theme.bgInput))
            Rectangle().fill(Color(nsColor: theme.border)).frame(height: 1)
            row(app: "Zed", title: "pika — README.md", age: "12s", selected: true)
            row(app: "Finder", title: "pika", age: "4m", selected: false)
        }
        .font(mono)
        .background(Color(nsColor: theme.bg))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: theme.border), lineWidth: 1))
        .accessibilityLabel("Preview of the switcher in the current theme")
    }

    private func row(app: String, title: String, age: String, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(selected ? Color(nsColor: theme.accent) : .clear).frame(width: 3)
            Text(app)
                .foregroundStyle(Color(nsColor: selected ? theme.accentAlt : theme.fgDim))
                .frame(width: 80, alignment: .leading)
                .padding(.leading, 10)
            Text("\(Text("pi").foregroundStyle(Color(nsColor: theme.accent)).bold())\(Text(title.dropFirst(2)).foregroundStyle(Color(nsColor: theme.fg)))")
            Spacer()
            Text(age).foregroundStyle(Color(nsColor: theme.fgDim)).font(.custom(PikaFont.family, size: 10)).padding(.trailing, 10)
        }
        .frame(height: 22)
        .background(selected ? Color(nsColor: theme.selBg) : .clear)
    }
}

private struct SearchPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingRow(model: model, title: "Recency weight", note: "How much recently used windows rise", key: "ranking.recency_weight") {
                        CommitSlider(model: model, key: "ranking.recency_weight", value: model.config.recencyWeight, range: 0...200, step: 5, format: { "\(Int($0))" }) {
                            model.set("ranking", "recency_weight", .double($0))
                        }
                    }
                    SettingRow(model: model, title: "Learn from my picks", note: "Remember which window you choose for each query", key: "ranking.learning") {
                        Toggle("", isOn: Binding(get: { model.config.learning }, set: { model.set("ranking", "learning", .bool($0)) })).labelsHidden()
                    }
                    SettingRow(model: model, title: "Learning weight", key: "ranking.learn_weight") {
                        CommitSlider(model: model, key: "ranking.learn_weight", value: model.config.learnWeight, range: 0...200, step: 5, format: { "\(Int($0))" }) {
                            model.set("ranking", "learn_weight", .double($0))
                        }
                    }
                    .disabled(!model.config.learning)
                    SettingRow(model: model, title: "List the current window", note: "Off keeps the previous window on top", key: "ranking.include_current") {
                        Toggle("", isOn: Binding(get: { model.config.includeCurrent }, set: { model.set("ranking", "include_current", .bool($0)) })).labelsHidden()
                    }
                }
                Section {
                    LabeledContent("Learned queries") {
                        Button("Forget All…") { model.confirmForgetLearned = true }
                    }
                }
            }
            .formStyle(.grouped)
            PaneFooter()
        }
        .confirmationDialog("Forget every learned query?", isPresented: $model.confirmForgetLearned) {
            Button("Forget All", role: .destructive) { model.perform(.learned) }
        } message: {
            Text("Pika will stop preferring the windows you've picked for each query. This can't be undone.")
        }
    }
}

private struct SourcesPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    SettingRow(model: model, title: "Chrome tabs", note: chromeNote, key: "sources.chrome_tabs") {
                        Toggle("", isOn: Binding(get: { model.config.chromeTabs }, set: { model.set("sources", "chrome_tabs", .bool($0)) })).labelsHidden()
                    }
                    if model.config.chromeTabs, model.chrome.grant == .denied {
                        HStack {
                            Text("Automation for Chrome is off in System Settings.").font(.callout).foregroundStyle(.orange)
                            Spacer()
                            Button("Open System Settings…") { StatusItemController.openSystemSettings(SystemSettingsPane.automation) }
                        }
                    } else if model.config.chromeTabs, case .notAsked = model.chrome {
                        HStack {
                            Text("macOS will ask you to let Pika control Chrome.").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow…") { model.requestChromeAccess() }
                        }
                    }
                } footer: {
                    Text("Windows from every app are always listed. Ghostty's native tabs appear as windows.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            PaneFooter()
        }
    }

    private var chromeNote: String {
        switch model.chrome.grant {
        case .granted: return "One row per tab"
        case .denied: return "Denied — one row per window"
        default: return "Needs Automation permission for Chrome"
        }
    }
}

private struct PrivacyPane: View {
    @Bindable var model: SettingsModel
    typealias Action = SettingsModel.PrivacyAction

    private struct StoredFile: Identifiable {
        let name: String
        let url: URL
        let contents: String
        var id: String { url.path }
    }

    private var files: [StoredFile] {
        let support = AppPaths.supportDirectory
        return [
            StoredFile(name: "config.toml", url: ConfigStore.shared.fileURL, contents: "Your settings"),
            StoredFile(name: "mru.json", url: support.appendingPathComponent("mru.json"), contents: "Recency: window titles and full Chrome tab URLs"),
            StoredFile(name: "learned.json", url: support.appendingPathComponent("learned.json"), contents: "Every query you typed and the target you chose"),
            StoredFile(name: "state.json", url: support.appendingPathComponent("state.json"), contents: "Setup progress and the last Chrome permission answer"),
            StoredFile(name: "icons/", url: IconCache.shared.directory, contents: "App icons, named by bundle ID"),
        ]
    }

    var body: some View {
        Form {
            Section {
                Text("Pika makes no network connections: no telemetry, analytics, or crash reports. What it keeps is on this Mac, in plain files:")
                    .font(.callout)
                ForEach(files) { file in
                    LabeledContent {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                            .disabled(!FileManager.default.fileExists(atPath: file.url.path))
                    } label: {
                        Text(file.name).font(.custom(PikaFont.family, size: 12))
                        Text(file.contents).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Link("Read the privacy notes", destination: URL(string: "https://github.com/tiagowright/pika#privacy-and-local-data")!)
                    .font(.callout)
            }
            Section {
                LabeledContent("Recency") { Button("Clear…") { model.privacyConfirm = .recency } }
                LabeledContent("Learned queries") { Button("Forget All…") { model.privacyConfirm = .learned } }
                LabeledContent("Icon cache") { Button("Delete…") { model.privacyConfirm = .icons } }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(title(for: model.privacyConfirm), isPresented: Binding(get: { model.privacyConfirm != nil }, set: { if !$0 { model.privacyConfirm = nil } }), presenting: model.privacyConfirm) { action in
            Button(button(for: action), role: .destructive) { model.perform(action) }
        } message: { action in
            Text(message(for: action))
        }
    }

    private func title(for action: Action?) -> String {
        switch action {
        case .recency: return "Clear recency?"
        case .learned: return "Forget every learned query?"
        case .icons: return "Delete cached icons?"
        case nil: return ""
        }
    }

    private func button(for action: Action) -> String {
        switch action {
        case .recency: return "Clear"
        case .learned: return "Forget All"
        case .icons: return "Delete"
        }
    }

    private func message(for action: Action) -> String {
        switch action {
        case .recency: return "The empty-query list will lose its most-recent-first order until you've switched around again."
        case .learned: return "Pika will stop preferring the windows you've picked for each query. This can't be undone."
        case .icons: return "Icons are rebuilt the next time Pika starts. Nothing else changes."
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Pika").font(.title.weight(.semibold))
            Text(version).font(.custom(PikaFont.family, size: 12)).foregroundStyle(.secondary)
            Text("A keyboard-first window switcher for macOS.").foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/tiagowright/pika")!)
                Link("Licences", destination: URL(string: "https://github.com/tiagowright/pika/blob/main/THIRD-PARTY.md")!)
            }
            Text("MIT licence · JetBrains Mono (OFL 1.1) · Catppuccin (MIT)").font(.caption).foregroundStyle(.secondary)
            Spacer().frame(height: 12)
            Button("Quit Pika") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v.map { "Version \($0)" } ?? "Development build"
    }
}
