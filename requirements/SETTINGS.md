# Pika — Settings, Onboarding, and Light Mode

Plan and requirements for three linked features:

1. A **settings window**, backed by the human-readable `config.toml`
2. An **onboarding flow** that walks the user through every permission and
   can be reopened from settings
3. A **light mode** (Catppuccin Latte), with a Dark / Light / Auto switch

Companion to `SHIPPING.md` §4.1–4.4, which already covers the menu bar
item, the O1–O5 onboarding screens, and Latte. **This document changes
some of those decisions**, listed in §0. Open questions are in §5 and are
referenced as **S1**…**S14**.

---

## 0. What this changes in SHIPPING.md

| SHIPPING.md says | This plan says | Why |
|---|---|---|
| §10: "A preferences window. The menu plus `config.toml` is the v1 surface." (deferred) | A settings window ships in v1 | The permission status, hotkey capture, and theme switch need a real surface, and the menu can't explain *why* a permission is missing |
| §4.3 principle 3: "It asks for exactly one permission." Chrome is left out of onboarding | Onboarding shows **every** permission in one checklist. Chrome is marked *optional* and can be skipped with one key | You asked for all permissions to be covered, with a clear record of what was skipped |
| §4.3: onboarding is a sequence of screens (O1 → O2 → O3 → O4) | Onboarding is built around one **permission checklist** that the settings window reuses (§2.3) | A linear flow loses track of a skipped step. A checklist always shows what's still missing |
| §4.3 O3: "immediately if Pika is present in the Accessibility list but switched off" | Not possible, so it's dropped | A sandbox-free app still can't read `TCC.db` without Full Disk Access. "Listed but off" and "never listed" both look like `AXIsProcessTrusted() == false` |
| §4.4.1: Latte uses the same Catppuccin roles for each token as Mocha | Latte uses **different roles** for `fg_dim`, `fg_muted`, `border`, and `sel_bg` | A one-to-one mapping fails contrast (§3.2) |

Everything else in SHIPPING §4.1–4.4 still applies: the menu bar item,
"Reset permissions", no silent login-item registration, and the rule that
config errors are reported to the user.

---

## 1. Settings

### 1.1 Principles

1. **`config.toml` is the source of truth for settings.** The settings
   window only views and edits it. Any change made in the window is written
   to the file right away, and any edit made to the file shows up in the
   window right away.
2. **The file stays hand-editable.** When Pika writes a value, it keeps the
   user's comments, blank lines, key order, and unknown keys. It never
   rewrites the whole file from a template.
3. **Not everything is a setting.** Facts owned by the OS (permissions, the
   login-item status) are shown live and are **not** stored in the file,
   because a stored copy would go stale. Pika's own bookkeeping (whether
   onboarding is done, the last Automation result) lives in `state.json`
   (SHIPPING §4.3).
4. **Every control maps to one config key**, and the window shows the key
   name. Hovering or pressing ⌥ reveals `appearance.theme = "auto"`, so the
   window also teaches the file format.

### 1.2 How users get to settings

With no Dock icon, a user needs more than one way in. Proposed, in order
of importance:

| # | Entry point | Notes |
|---|---|---|
| E1 | **Menu bar item → Settings… (⌘,)** | Main entry point. The SHIPPING §4.1 menu becomes shorter because the permission rows move to the window (see §1.5) |
| E2 | **Opening Pika.app again** from Finder, Spotlight, Raycast, or Launchpad while it's running opens Settings | `applicationShouldHandleReopen` / a second launch. A user who can't find the menu bar icon (on a crowded menu bar, or hidden by Bartender or Ice) will try this first. This is also the only way back in if the status item is ever made hideable (SHIPPING §10) |
| E3 | **⌘, while the switcher panel is open** closes the panel and opens Settings | Works from the keyboard, costs nothing, and follows the usual macOS convention |
| E4 | **Warning badge** on the status item icon when a *required* permission is missing, or the hotkey failed to register | Clicking the badge opens Settings → Permissions directly |
| E5 | *Option:* a command typed in the switcher (for example `>settings`) | Keyboard-first, but it adds a command layer to a product that only lists what's open (UX §1.6). **S3** |
| E6 | *Deferred:* `pika://settings` URL scheme and a `pika` CLI | Useful for scripting later. Not needed in v1 |

### 1.3 Implementation options

**Option A — Native SwiftUI window (recommended).**
Use an `NSWindow` hosting a SwiftUI `TabView` (or a sidebar layout, as in
System Settings), with standard controls.

- Toggles, sliders, pickers, VoiceOver, and keyboard navigation come for
  free
- A hotkey recorder is a small, well-understood control
- It follows `NSApp.appearance`, so the Dark/Light/Auto setting (§3)
  controls the window too
- It doesn't use the terminal look. That's reasonable: the window is used
  rarely, and a native look signals "this is where you configure things"
- Cost: roughly 400–600 lines, and SwiftUI enters the build. SwiftPM
  already supports this; no Xcode project is needed

**Option B — Terminal-styled window in Pika's visual language.**
JetBrains Mono, Catppuccin colours, `❯` prompts, keyboard-driven rows
(like the onboarding mock-ups in SHIPPING §4.3).

- Consistent with the brand, and memorable
- Every control (slider, picker, hotkey recorder) has to be built by hand
  in `draw(_:)`, and accessibility is also manual
- About 2–3 times the cost of Option A

**Option C — Hybrid.** A native SwiftUI window, styled with Catppuccin
colours and JetBrains Mono for headings and key names. Native controls
inside. This keeps most of Option A's low cost while keeping some brand
feel. **S1**

**Option D — No window: menu plus "Open config file".**
This is the current SHIPPING plan. It's rejected because it can't handle
live permission state or hotkey capture well.

**Activation.** Pika is an `.accessory` app. The settings window calls
`NSApp.activate()` and becomes key normally. The switcher panel stays a
`.nonactivatingPanel` and is never rebuilt (TECHNICAL §9). Opening Settings
must not disturb the prewarmed panel or the MRU stack. Pika's own settings
window must be excluded from the list (UX §9, "Pika's own panel").

### 1.4 Config file: reading, writing, and watching

| # | Requirement |
|---|---|
| 1.4.1 | **One live `ConfigStore`** (an observable object) replaces the separate `Config.loadOrCreateDefault()` calls in `AppDelegate` and `PanelController` (SHIPPING §4.1.7). The panel, the hotkey manager, the sources, and the settings window all subscribe to it |
| 1.4.2 | **Writing without losing formatting.** Keep the parser's line model: each line is a `(section, key, value, trailing comment, raw text)`. To set a key, replace only the value on that line and keep the trailing comment. If the key is missing, add it at the end of its section. If the section is missing, add the section at the end of the file. Write atomically. Round-trip test: parse, then serialise, must reproduce the file byte-for-byte |
| 1.4.3 | **Watch the file** with a `DispatchSource` file-system watcher. Watch the directory as well, because editors that save atomically replace the file's inode. Reload after ~150 ms of quiet so partial saves are ignored. Changes made by Pika itself don't trigger a reload loop (compare the content hash) |
| 1.4.4 | **Report problems.** For unknown keys, bad values, or a hotkey that can't be parsed, the settings window shows a banner such as "config.toml line 12: `theme = "latt"` is not a known theme — using Auto". The status item gets a badge. The value that was actually applied is shown. The file is **never** "fixed" automatically |
| 1.4.5 | **Validation on write.** The window can only produce valid values. Sliders and fields are limited to the same ranges the parser accepts |
| 1.4.6 | Header comment in `defaultText`: "Edited by hand or by Pika → Settings. Pika keeps your comments." Every key gets a short comment that lists its allowed values |
| 1.4.7 | *Nice to have:* a **Reset to defaults** button per section, and **Open config.toml** / **Reveal in Finder** buttons in the window |

### 1.5 What the settings window contains

Each item shows its tab, control, config key, and notes. Items marked
**new** have no config key today.

**General**
- Hotkey: a recorder control plus a live status of "registered ✓" or
  "taken by another app ✗" (from the `RegisterEventHotKey` `OSStatus`,
  SHIPPING §4.2). If the hotkey is `ctrl+space`, show a note about the
  macOS Input Sources conflict with a button that opens that settings page.
  Key: `hotkey`
- Launch at login: a toggle that reflects `SMAppService.mainApp.status`.
  It's owned by the OS and **not** stored in the file (**S5**)
- Show menu bar icon: *deferred* (SHIPPING §10). It needs E2 working first

**Permissions**: the shared permission checklist (§2.3), plus
- Run setup again… (opens onboarding, §2)
- Reset permissions… (SHIPPING §4.1.5)

**Appearance**
- Theme: a Dark / Light / Auto picker, with a live preview swatch of a
  mini switcher row. Key: `appearance.theme` (**S9**)
- Font size, panel width, max rows. Keys: `font_size`, `width`, `max_rows`
- Show icons. Key: `show_icons`
- Cursor blink. Key: `appearance.cursor.blink`
- `font` stays documented as "bundled JetBrains Mono". Either implement the
  key or remove it from `defaultText` (**S12**)

**Search & ranking**
- Recency weight, learning on/off, learn weight, include current window.
  Keys: `[ranking]`
- Forget learned queries… (`LearnedStore.forgetAll`), with a confirmation

**Sources**
- Chrome tabs: a toggle, with the live Automation status next to it.
  Turning it on while the status is "not asked" starts the Automation
  request (§2.4). Key: `sources.chrome_tabs`

**Privacy & data**
- A list of the files Pika stores (the table from the README), each with a
  Reveal button
- Clear recency data, clear learned data, clear icon cache
- A link to the README privacy section

**About**
- Version, a GitHub link, licences (MIT, OFL, and Catppuccin MIT), and
  Quit Pika

**Menu bar menu, after this change** (shorter than SHIPPING §4.1):

```
  Pika 0.1.0
  ⚠ Accessibility not granted — Fix…    (only when something is wrong)
  ───────────────
  Settings…                          ⌘,
  Theme              ▸  Auto / Dark / Light
  ───────────────
  Quit Pika                          ⌘Q
```

---

## 2. Onboarding and permissions

### 2.1 What Pika needs

| Item | Kind | Required | How to detect | How to request |
|---|---|---|---|---|
| **Accessibility** | TCC | **Yes** | `AXIsProcessTrusted()`, which is cheap enough to poll | `AXIsProcessTrustedWithOptions(prompt: true)` works only the first time. After that, deep-link to `Privacy_Accessibility` |
| **Automation → Google Chrome** | TCC (Apple Events) | Optional | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` → `noErr` means granted, `-1743` denied, `-1744` not yet asked, `-600` Chrome not running. This checks **without** sending an event | The same call with `askUserIfNeeded: true` shows Apple's dialog. **Chrome must be running.** If the user denied it, deep-link to `Privacy_Automation`. Pika only appears in that list after it has asked once |
| **Launch at login** | Consent (not TCC) | Optional | `SMAppService.mainApp.status` | `register()` / `unregister()`. `.requiresApproval` deep-links to Login Items |
| **Hotkey** | Health check (not a permission) | Yes, in practice | `RegisterEventHotKey` `OSStatus` | Record a different hotkey |
| Screen Recording, Input Monitoring | — | **Never** | — | Say so explicitly on screen, because it builds trust |

Code gap found while writing this: `ChromeTabSource.refresh` retries with
back-off on **any** AppleScript error, including `-1743` (denied). It keeps
retrying every 20 s for the rest of the session. It should record `-1743`
in `state.json`, stop retrying, and let the checklist show "denied". A
change to Chrome's permission should restart it.

### 2.2 Design options for the flow

**Option 1 — Linear wizard** (the SHIPPING §4.3 screens, extended with a
Chrome screen). It's simple to follow, but a skipped step disappears. You
only learn it was skipped if you rerun the wizard.

**Option 2 — Checklist-first (recommended).** Onboarding has three short
parts:

1. **Welcome.** One screen: what Pika does, what it will ask for, and that
   nothing leaves the machine.
2. **Checklist.** Every item from §2.1 in one list. Each row shows its
   status, one sentence on *why* it's needed, and **one button that does
   the right thing for the current state**. Required rows are marked. The
   user can work through the rows in any order. "Continue" is enabled once
   the required rows are green. Optional rows can be left as they are,
   and they stay visibly unchecked.
3. **Try it.** "Press ctrl+space now." This detects the press, shows the
   real panel, and ends onboarding (SHIPPING Q4).

The **same checklist component** appears in Settings → Permissions. Two
things address "the user skipped it and now it's unclear": the list always
shows current status, and the menu bar badge (E4) appears whenever a
required item is red.

**Option 3 — Guided overlay.** Like Option 2, but opening System Settings
also shows a small floating helper window beside it. The helper shows the
Pika.app icon, which can be dragged into the Accessibility list, and an
arrow pointing to the toggle. This is the pattern used by apps like
Rectangle, Ice, and the `PermissionsKit` / `Permiso` libraries. It fixes the most common failure (can't find
Pika in the list, or it isn't in the list), but it's the most work, and
positioning the helper next to System Settings is fragile across macOS
versions. **S7**

### 2.3 The permission checklist (shared component)

```
  Accessibility                    required    ✓ granted
    read window titles and raise the one you pick

  Chrome tabs (Automation)         optional    ○ not asked yet     [ Allow… ]
    list individual Chrome tabs, not just windows

  Start at login                   optional    ✓ on                [ Turn off ]

  Hotkey  ctrl+space                           ✗ taken             [ Change… ]
    another app or macOS already uses it
```

| # | Requirement |
|---|---|
| 2.3.1 | **Status is live and never guessed.** Accessibility is polled every 1 s while the window is visible. Everything else is re-checked on `NSApplication.didBecomeActiveNotification`, which fires when the user returns from System Settings, and when the window appears. Nothing is polled while the window is hidden |
| 2.3.2 | **States:** `granted` ✓ green · `not asked` ○ neutral · `denied` ✗ red for required items, amber for optional · `needs Chrome running` ⏸ neutral, with a [ Open Chrome ] button · `skipped` for an optional item the user dismissed (stored in `state.json`, shown in muted text, and not nagged about) |
| 2.3.3 | **One button per state.** Not asked → request (system prompt). Denied → open the exact System Settings pane, and show the path in text below the row ("Privacy & Security → Automation → Pika → Google Chrome"). Granted → no button, or a secondary "Open in System Settings" |
| 2.3.4 | **The row updates when permission is granted.** On grant, the row turns green with no click needed. If onboarding is showing and the last required row just turned green, bring Pika's window back to the front (the user is still in System Settings) |
| 2.3.5 | **Troubleshooting inside the row.** Accessibility still red 20 s after the user opened System Settings (**S8**)? Expand the row with the SHIPPING O3 content: "not in the list → drag it in", "in the list but won't stick → Reset permissions", and a copyable `tccutil` command. After a rebuild with a changed signature, this is the most common problem (`CODE_SIGNING.md`) |
| 2.3.6 | **Accessibility labels.** Every status has a text label as well as its colour and glyph, so VoiceOver reads it and it doesn't rely on colour alone (this also affects the Latte `warn` colour, §3.2) |

### 2.4 Flow rules

| # | Rule |
|---|---|
| 2.4.1 | Onboarding runs when `state.json` is missing, or when `onboardingVersion` < the build's version. In that case only the new rows are highlighted (SHIPPING Q10). It also runs from Settings → Permissions → **Run setup again**, which always starts at Welcome and shows the current state (SHIPPING Q6) |
| 2.4.2 | If Accessibility is already granted at first launch (for example, a reinstall), skip straight to the checklist with that row already green. Don't skip the checklist, because the optional rows still need a decision |
| 2.4.3 | **Chrome in onboarding.** If Chrome is running, [ Allow… ] shows Apple's dialog immediately, in context, with Pika's explanation already on screen. That settles SHIPPING Q5. If Chrome isn't running, the row reads "Chrome isn't open — Pika will ask the first time it sees Chrome", and the item is stored as consent-to-ask (SHIPPING O5) |
| 2.4.4 | **Skipping.** Optional rows get a small "Skip". A skipped item is shown as skipped, never as an error, and it produces no badge |
| 2.4.5 | **Esc / closing the window during onboarding.** If Accessibility is still missing, the app stays running with a red badge on the status item. This differs from SHIPPING Q1 ("quit"), because with a badge the user can still find a way back (**S6**) |
| 2.4.6 | Launch at login is **never** registered silently. It happens only through the checklist toggle or Settings (SHIPPING §4.1.6) |

---

## 3. Light mode — Catppuccin Latte

### 3.1 The mode switch

- Three values: **Auto** (follow macOS), **Dark** (Mocha), **Light**
  (Latte). Default: **Auto** (SHIPPING Q11)
- Config: `appearance.theme = "auto" | "dark" | "light"`. The flavour names
  `catppuccin-mocha` and `catppuccin-latte` are also accepted as aliases,
  so existing files keep working. **S9** covers whether each mode should
  get its own flavour key
- Auto observes `NSApp.effectiveAppearance` using KVO, and repaints the
  panel and border live without rebuilding the panel (SHIPPING §4.4.5)
- The same setting sets `NSApp.appearance` (`nil` / `.darkAqua` / `.aqua`),
  so the settings window and onboarding follow it too
- Available in three places: Settings → Appearance, the menu bar Theme
  submenu, and the config file

### 3.2 Latte token mapping and contrast

The palette was checked against `catppuccin/palette` (palette.json, fetched
2026-09-28). The ten Latte hex values listed in SHIPPING §4.4.1 all match.
**The mapping itself doesn't work.** The Catppuccin style guide
(`docs/style-guide.md`) assigns colours by *role*: subtle text = Overlay 1,
labels = Subtext 0/1, selection background = Overlay 2 at 20–30 % opacity,
cursor = Rosewater, warnings = Yellow. It also says: "Legibility always
comes first … use your own judgement." Latte's overlays sit much closer to
its background than Mocha's do, so the same role gives much lower contrast.

WCAG contrast ratios, measured on `bg` (base) unless noted. AA for body
text is 4.5:1. Non-text UI and large text need 3:1.

| Token | Used for | Mocha (today) | Latte, same role | Latte **proposed** |
|---|---|---|---|---|
| `bg` | panel | base `#1e1e2e` | base `#eff1f5` | base `#eff1f5` |
| `bg_input` | query row | mantle `#181825` | mantle `#e6e9ef` | mantle `#e6e9ef` |
| `fg` | titles | text — 11.3 | text `#4c4f69` — **7.1** ✓ | text `#4c4f69` — 7.1 ✓ |
| `fg_dim` | app name (unselected), recency column | overlay1 — 4.4 | overlay1 `#8c8fa1` — **2.8** ✗ | **subtext0 `#6c6f85` — 4.4** (the same contrast as Mocha), or subtext1 `#5c5f77` — 5.5 for strict AA (**S10**) |
| `fg_muted` | placeholder, empty state | overlay0 — 3.4 | overlay0 `#9ca0b0` — **2.3** ✗ | **overlay2 `#7c7f93` — 3.5** (same contrast as Mocha) |
| `accent` | `❯`, selection bar, matched chars, cursor | mauve — 8.1 | mauve `#8839ef` — 4.8 on base, 4.5 on mantle, **3.5 on surface0** | mauve. Also draw matched characters **semibold** in Latte (or in both themes), so the fuzzy-match highlight doesn't depend on hue alone at 3.5:1 |
| `accent_alt` | app name on the selected row | blue — 6.0 on sel | blue `#1e66f5` — **3.2** on surface0 | blue. It reaches 3.5 on the proposed `sel_bg`. Acceptable for a short label next to the title, and flagged |
| `sel_bg` | selected row | surface0 | surface0 `#ccd0da` (text 5.2) | **overlay2 at 20 % over base → `#d8dae1`**, exactly as the style guide describes: text 5.7, mauve 3.9, blue 3.5. Stored as a solid hex so drawing stays cheap |
| `border` | 1 pt panel edge | surface1 — 1.8 | surface1 `#bcc0cc` — **1.6**, and invisible against a white window behind the panel | **overlay0 `#9ca0b0` — 2.3** (the style guide's "inactive border"). The panel has no shadow (UX §1.3), so the border alone separates Pika from a light app behind it (**S11**) |
| `warn` | degraded-source marker | yellow — 12.9 | yellow `#df8e1d` — **2.3** ✗ (under 3:1) | Keep yellow, as the style guide specifies, but **never use colour alone**. The marker must be a distinct glyph. The alternative is peach (2.6), which still fails. No Latte warm colour passes 3:1 on base except red, which means "error" (**S11**) |
| cursor | block cursor | accent at 85 % | — | Stay on `accent` (it's part of the brand look). The style guide suggests Rosewater, which is optional |

Requirements:

| # | Requirement |
|---|---|
| 3.2.1 | `Theme.catppuccinLatte` uses the **proposed** column. `UX.md` §7 gains a Latte column with a note that the roles are intentionally different |
| 3.2.2 | A unit test (the first one in the repo, and a cheap one) asserts minimum contrast ratios per token pair for both themes, so a future palette change can't quietly lower them |
| 3.2.3 | Check both themes on screen against a busy dark window and a busy light window behind the panel. The border and `sel_bg` choices only hold up if they look right in practice |
| 3.2.4 | Icons: app icons are full colour and work on both. Test a few that are nearly white (Notes, Safari) on Latte `bg` |
| 3.2.5 | THIRD-PARTY / README: the Catppuccin notice covers Latte. Update the README "theme is fixed" note |

---

## 4. Suggested build order

1. **`ConfigStore`**: a single observable config, format-preserving writer,
   file watcher, and error reporting (§1.4). Everything else depends on
   this. ✅ *Done 2026-09-28*: `Sources/Pika/Config/`, tests in
   `Tests/PikaTests/`. Problems are logged only for now; the badge and
   the banner arrive with steps 3 and 5
2. **Theme**: add Latte, the Auto/Dark/Light switch, and live repaint (§3).
   It's small and gives a visible result quickly, and it tests
   `ConfigStore` end to end. ✅ *Done 2026-09-28*: `UI/Appearance.swift`,
   contrast floors in `ThemeContrastTests`, and an opt-in panel render
   (`PIKA_SNAPSHOT_DIR=… swift test --filter PanelSnapshotTests`). The
   menu bar Theme submenu arrives with step 3
3. **Menu bar status item**: the short menu, badge, and Quit (§1.5).
   ✅ *Done 2026-09-28*: `UI/StatusItemController.swift`,
   `UI/MenuBarIcon.swift`, `SystemShortcuts.swift`. Problems listed in the
   menu: Accessibility missing, hotkey taken by another app, hotkey
   shadowed by a macOS shortcut, and config.toml issues (retired keys are
   notices and don't badge). Until step 5, "Open config.toml…" (⌘,) stands
   in for Settings…
4. **Permission model**: a `PermissionCenter` that reports live state for
   the four items, the `AEDeterminePermissionToAutomateTarget` check, the
   Chrome `-1743` fix, and `state.json`
5. **Settings window**: tabs wired to `ConfigStore` and `PermissionCenter`,
   plus the hotkey recorder and entry points E1–E3
6. **Onboarding**: Welcome → checklist → try-it, reusing the checklist
   component

---

## 5. Questions before implementation

- **S1 — Settings window style.** Native SwiftUI (A), terminal-styled (B),
  or hybrid (C)? *Recommendation: C, a native window with Catppuccin
  accents.*
- **S2 — Onboarding style.** Same question for onboarding. SHIPPING §4.3
  proposed the terminal-panel look. *Recommendation: use the same window
  as Settings, so the checklist component is built only once.*
- **S3 — A switcher command (E5)?** Should typing `>settings` in the panel
  open Settings, or should the panel stay pure (just ⌘,)?
  *Recommendation: ⌘, only for now.*
- **S4 — Where do menu bar changes go?** Should changing the theme from the
  menu write to `config.toml` (the file stays the source of truth)?
  *Recommendation: yes. This is SHIPPING Q9 option (a), which this plan
  depends on.*
- **S5 — Launch at login in the file?** Should `config.toml` have a
  `launch_at_login` key, or should the setting be shown only in the UI,
  because macOS owns it and the user can change it in System Settings
  without Pika knowing? *Recommendation: UI only, with a comment in the
  file explaining where it lives.*
- **S6 — Closing onboarding without Accessibility.** Should Pika quit
  (SHIPPING Q1), or keep running with a red badge (§2.4.5)?
  *Recommendation: keep running with the badge.*
- **S7 — Guided overlay (Option 3)?** Is the drag-the-icon helper next to
  System Settings worth building for v1, or should it wait?
  *Recommendation: v1.1. Ship the inline troubleshooting (2.3.5) first.*
- **S8 — Troubleshooting delay.** How long before the Accessibility row
  expands into troubleshooting? *Recommendation: 20 s.*
- **S9 — Theme config shape.** Should `theme = "auto" | "dark" | "light"`
  be a single key, or should it also have `dark_theme` / `light_theme`
  keys naming the flavours (ready for Frappé and Macchiato later)?
  *Recommendation: single key now. Add the flavour keys when a third
  flavour ships.*
- **S10 — `fg_dim` on Latte.** Should it be subtext0 (4.4:1, the same
  contrast as Mocha) or subtext1 (5.5:1, strict AA, but a smaller
  difference from `fg`)? *Recommendation: subtext0.*
- **S11 — Deviations from the style guide on Latte.** Are you OK with a
  darker border (overlay0) and a yellow `warn` that only passes contrast
  because it's paired with a glyph? Or would you prefer a
  stricter-contrast option that departs further from the Catppuccin
  roles? *Ok with the overlay0*
- **S12 — The `font` key.** Implement it (any installed monospace font) or
  remove it from the default config? *Recommendation: remove it for v1,
  because the bundled font is part of the look.*
- **S13 — Semibold matched characters.** Latte only, or both themes?
  *Recommendation: both, so the two themes behave the same.*
- **S14 — Scope.** Is all of this a v1 blocker (added to SHIPPING §4), or
  should Settings ship after the menu-bar + onboarding + Latte release?
  *this is all v1 blocker*
