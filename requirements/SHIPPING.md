# Pika — Shipping Requirements (v1 public release)

The minimal set of work between the current repo and a public GitHub repo
that a stranger can install and run. Companion to `UX.md` and
`TECHNICAL.md`; those describe the product, this describes what it takes
to hand it to someone else.

**Decisions taken** (2026-09-21): MIT license · notarized release *and*
build-from-source · as-is, no support · the product gaps in §4 are ship
blockers, not known limits · a menu bar status item ships, and it is the
re-entry point for permissions and theme · privacy disclosure lives in
the README, **not** a separate `PRIVACY.md` · Catppuccin **Latte** ships
alongside Mocha in v1.

**Decisions taken** (2026-09-28, detailed in `SETTINGS.md`): a settings
window ships in v1, reversing its deferral in §10 · onboarding covers
every permission in one checklist · `theme = "auto"` is the default ·
`config.toml` stays the single source of truth, and Pika edits it in
place. §4.1–4.4 have shipped; their sections now record what was built.

Everything here is a blocker unless marked *Nice to have*. Anything not
listed is explicitly deferred — see §10. Open decisions are collected in
§9; the body references them as **Q1**…**Q14**.

---

## 1. Why this list exists

Pika is unusually demanding of a new user's trust. It is an invisible
background agent, it asks for Accessibility — the most powerful
permission macOS grants — it reads every window title on the machine and
every Chrome tab title and URL, and it runs at login. Each of those is
defensible. (The two gaps this list originally named — silent login-item
registration and no way to quit — are closed by §4.1.)

The other half of the list is mechanical: the repo does not build for
anyone else yet.

---

## 2. The repo must build for someone who is not you

| # | Requirement | Why |
|---|---|---|
| 2.1 | ✅ **Done** (2026-09-21). `build.sh` resolves the identity `$PIKA_SIGN_IDENTITY` → `.signing-identity` (gitignored, per-clone) → a Developer ID Application certificate → ad-hoc. The `.signing-identity` step was added beyond the original plan so a maintainer holding only a self-signed local cert does not silently fall through to ad-hoc. | A fresh clone no longer fails at `codesign`. |
| 2.2 | ✅ **Done** (2026-09-21). Signing ad-hoc prints a stderr warning naming the symptom ("Pika silently stops raising windows after each rebuild") and the fix, with the Keychain Access steps in the README. | The ad-hoc path is the one most contributors take, and the symptom is baffling without the explanation. |
| 2.3 | ✅ **Done** (2026-09-21). `install.sh` prints the four things it is about to do — naming the running process and the directory it will delete — and asks before doing any of them. `--yes` / `-y` skips it for non-interactive use; an unknown argument exits 2 with usage. Build-from-source is documented in the README as the only current path. | Running a script off the internet that kills processes and writes to `/Applications` is a fair thing to be cautious about. |
| 2.4 | ✅ **Done** (2026-09-21). Floor raised to the tested one: `Package.swift` is `.macOS("26.0")` and `LSMinimumSystemVersion` is `26.0`, verified by a clean release build. Lower it only after testing on the version claimed. | No longer claims macOS 13 support that was never exercised. |
| 2.5 | ✅ **Done** (2026-09-21). README states macOS 26+, Apple Silicon, Swift 6.4, and that Command Line Tools suffices — full Xcode is not needed. `TECHNICAL.md` corrected from 6.3 to 6.4. | Toolchain facts now match the build machine. |
| 2.6 | 🟡 **Found and mitigated** (2026-09-21), worth a proper fix. `build.sh` leaves `Pika.app` in the project directory and `install.sh` used to copy it to `/Applications` without removing it — leaving two bundles with the same `CFBundleIdentifier`. macOS resolves an identifier to a path through Launch Services to draw the Privacy & Security rows, so the second candidate makes the app **impossible to add to Accessibility**: the row silently never appears, with no error anywhere. `install.sh` now deletes the intermediate, and the README warns about using `build.sh` alone. A real fix builds into a scratch location so a stray bundle cannot exist. | Cost an hour to diagnose, and the symptom points at everything except the cause. The bundle-identifier change in §3.5 is what exposed it — with both copies sharing the old identifier and only one path ever granted, the ambiguity was never tested. |

---

## 3. Distribution

Both channels ship. The notarized build is the default the README points
at; source is for people who want to read it first.

| # | Requirement |
|---|---|
| 3.1 | Developer ID Application certificate, `codesign --timestamp --options=runtime`, submitted through `notarytool`, stapled with `stapler`. An un-notarized download is quarantined and Gatekeeper blocks it outright. |
| 3.2 | A `release.sh` (or GitHub Actions workflow) that produces a stapled `Pika-<version>.dmg` or `.zip` from a clean checkout, so releases are reproducible and not a thing you remember how to do. |
| 3.3 | Notarization credentials live in GitHub Actions secrets or a local keychain profile — never in the repo. Verify `git log -p` has never contained a certificate, an app-specific password, or a Team ID you consider private. |
| 3.4 | Tag the release (`v0.1.0`) and bump `CFBundleShortVersionString` / `CFBundleVersion` in `build.sh` from a single source of truth. They currently read `0.1` / `1` and will silently stay there. The menu bar item (§4.1) displays this string, so a stale version is now visible to users. |
| 3.5 | ⚠️ **Changed once, deliberately, now frozen** (2026-09-21): `dev.pika.app` → `io.github.tiagowright.pika`, because the old identifier implied ownership of `pika.dev`. `io.github.<user>` is a namespace that genuinely is yours. The data directories were renamed to match and the existing `learned.json` / `mru.json` migrated across. **This is the last time it changes** — it is public-facing from the first release, and changing it or the signing identity revokes the user's Accessibility grant with no error message. |
| 3.6 | *Nice to have:* a Homebrew cask. It needs the notarized artifact first, so it is strictly downstream of 3.1. |

---

## 4. Product gaps that block a public release

### 4.1 The menu bar item is the control surface

✅ **Shipped** (2026-09-28/29). The
design moved on from the menu sketched here: permissions, launch at
login, and data actions live in a settings window, and the menu stays
short. Full design in `SETTINGS.md` §1.

```
  Pika 0.1                                    (disabled, from CFBundleShortVersionString)
  ⚠ Grant Accessibility…                      (problem rows appear only when something is wrong)
  ───────────────
  Settings…                               ⌘,
  Theme              ▸  Auto (follow macOS) / Dark — Mocha / Light — Latte
  ───────────────
  Quit Pika                               ⌘Q
```

| # | Requirement | Status |
|---|---|---|
| 4.1.1 | Status item | ✅ A simplified leaping pika (`pika-glyph-{mocha,latte}.svg`, drawn by `PikaGlyph.swift`) in Mocha on a dark menu bar and Latte on a light one; an orange dot when something needs the user. |
| 4.1.2 | Permission state live, "not yet asked" distinct from "denied" | ✅ `PermissionCenter` — `AXIsProcessTrusted()`, and `AEDeterminePermissionToAutomateTarget` for Chrome, which checks without prompting. Re-checked on menu open, on leaving System Settings, on Chrome launch/quit. |
| 4.1.3 | Deep links to the Accessibility and Automation panes | ✅ In use from the menu, Settings, and onboarding. Accessibility confirmed on macOS 26 by use; the Automation and Keyboard links are not yet confirmed. |
| 4.1.4 | Re-enter first-run setup | ✅ Settings → Permissions → **Run Setup Again…**. |
| 4.1.5 | Reset permissions | 🟡 Settings shows the `tccutil reset` command with a **Copy** button. Whether Pika may run it on itself (**Q12**) is still untested. |
| 4.1.6 | Launch at login opt-in | ✅ Never registered silently: only from onboarding or Settings → General, which reflects `SMAppService.mainApp.status`. |
| 4.1.7 | Reload config without relaunch | ✅ Better than a menu item: `ConfigStore` watches `config.toml` and applies edits on save. One live config replaces the separate loads. |
| 4.1.8 | `uninstall.sh` | ❌ Not done. The README's uninstall commands remain the path. |

### 4.2 Silent failures must speak

✅ **Shipped.**

- **Hotkey.** `HotKeyManager` keeps the `RegisterEventHotKey` result, and
  `SystemShortcuts` reads `com.apple.symbolichotkeys` for clashes with
  macOS's own shortcuts. That second check matters most:
  `RegisterEventHotKey` *succeeds* for `ctrl+space` while macOS's Input
  Sources shortcut takes the keypress first. Either problem badges the
  menu bar icon, and the menu and Settings → General name the clash and
  offer the fix (a hotkey recorder, or the Keyboard Shortcuts pane).
- **Config.** Malformed lines, unknown keys and sections, wrong types,
  out-of-range values, duplicate keys and bad hotkeys are each reported
  with a line number, in the menu and as a banner in Settings. The rest
  of the file still applies. Leftover keys that do nothing (`font`) are
  notices and don't badge.
- **`theme =`** is read (§4.4).

### 4.3 Onboarding (first run)

✅ **Shipped** (2026-09-29). The O1–O5 terminal-panel screens planned here
were replaced by a checklist-first design in a native window; the
reasoning is in `SETTINGS.md` §2.2, and the shipped behaviour is in
`SETTINGS.md` §4 step 6. In short:

1. **Welcome**: what Pika does, what it will ask for, and what it never
   asks for (Screen Recording, Input Monitoring).
2. **Checklist**: Accessibility (required), Chrome tabs (optional),
   Start at login (optional), and the hotkey (required). Each row shows
   live status, why it's needed, and one button that does the right thing
   for its state. Optional rows can be skipped; skipping Chrome also sets
   `chrome_tabs = false`, so the Automation prompt never arrives
   unexplained. If Accessibility is still off 20 s after the user was
   sent to System Settings, the row expands into troubleshooting (the old
   O3). Continue needs Accessibility and a hotkey that will fire.
3. **Try it**: pressing the hotkey finishes setup and opens the switcher.

Differences from the original plan, all decided in `SETTINGS.md`:

- No system prompt fires at launch; the Accessibility row asks.
- Chrome Automation is part of the checklist rather than a surprise
  after it (settles Q5).
- While Setup or Settings is open, Pika is a regular app (Dock icon,
  ⌘Tab) so the user can go to System Settings and come back, and it
  activates outright (`AppPresence.swift`).
- Closing Setup early counts as done once Accessibility is granted;
  otherwise it returns next launch, and the menu bar badge points the way.
- **Completion state**: `state.json` holds `onboardingVersion`,
  `onboardingCompletedAt`, `skipped`, and the last Chrome answer.
  Highlighting only new rows for upgraders (Q10) waits for a second
  onboarding version.

### 4.4 Catppuccin Latte (new feature)

✅ **Shipped** (2026-09-28). `theme = "auto" | "dark" | "light"`, default
`auto`, which follows macOS and repaints the prewarmed panel live. The old
flavour names are accepted as aliases. Selectable from the menu, Settings
→ Appearance (with a preview), and `config.toml`.

| # | Requirement | Status |
|---|---|---|
| 4.4.1 | `Theme.catppuccinLatte`, hex verified | ✅ All values checked against `catppuccin/palette`. |
| 4.4.2 | Re-check tokens tuned for a dark panel | ✅ The one-to-one mapping proposed here failed contrast (dim text 2.8:1). Latte uses subtext0, overlay2, overlay0 for the border, and overlay2 at 20% for the selection; matched characters are semibold in both themes. Reasoning in `SETTINGS.md` §3.2; floors enforced by `ThemeContrastTests`. |
| 4.4.3 | `Config.parse` reads `theme`, reports unknown values | ✅ (Q11: `auto` ships). |
| 4.4.4 | Theme submenu that persists | ✅ Writes `config.toml` in place, keeping comments (Q9 option a). |
| 4.4.5 | Runtime switching without rebuilding the panel | ✅ `Appearance.swift`; the panel and its border repaint in place. |
| 4.4.6 | `defaultText` documents the values | ✅ |
| 4.4.7 | `UX.md` §7 Latte column; attribution | ✅ |

### 4.5 Privacy and permissions, in writing — in the README

**No `PRIVACY.md`.** A separate file is one more click away from the
person deciding whether to trust this, and it will drift. The disclosure
is a README section, linked from the top, and it is the same text
Settings → Privacy & Data links to ("Read the privacy notes").

It must state plainly:

- Pika reads the **title of every window on the machine** via the
  Accessibility API, and, if Automation is granted, the **title and URL
  of every Chrome tab**.
- It writes to disk, in `~/Library/Application Support/io.github.tiagowright.pika`:
  `mru.json` (bundle IDs, window titles, and — because
  `TargetID.tab(bundleID:url:)` uses the URL as the discriminator —
  **Chrome tab URLs**) and `learned.json` (**every search query you
  type**, mapped to the target you picked). Icon bitmaps land in
  `~/Library/Caches/io.github.tiagowright.pika/icons`, named by bundle ID — the filenames
  alone reveal which apps you run. Whether any of it is encrypted is §5;
  whatever §5 concludes, this section states the truth about it.
- **Window titles reach the unified system log.** `ChromeTabSource`
  logs an AX window title at `privacy: .public`
  (`Sources/Pika/Sources/ChromeTabSource.swift:153`), and AppleScript
  error payloads at `.public` may contain more. Either mark those
  interpolations `.private` or disclose that titles appear in
  `log show` output and in a sysdiagnose. Marking them private is the
  better answer; the issue template (§6.5) asks for logs, and a bug
  report should not carry the reporter's window titles.
- **Nothing leaves the machine.** There is no network code, no
  telemetry, no crash reporting, no analytics. Say it explicitly; it is
  the single most reassuring sentence in the document.
- Which permissions are requested, which are required, and — worth
  stating, per `TECHNICAL.md` §6 — which are deliberately *not*:
  Screen Recording and Input Monitoring are avoided by design.
- How to see and delete the data: the paths above, Settings → Privacy &
  Data (show each file in Finder, clear recency, forget learned queries,
  delete the icon cache), and `uninstall.sh` (§4.1.8, not yet written —
  the README's commands stand in).
- How long it keeps it: recency entries expire after 30 days (at most
  10,000), learned queries fade 2% a day (at most 500).

---

## 5. Data at rest — what encryption would actually take

### 5.1 What is on disk today

| Path | Contents | Worst case if read |
|---|---|---|
| `…/Application Support/io.github.tiagowright.pika/mru.json` | `bundleID\0discriminator` → timestamp, plus a `bundleID\0title:<title>` fallback key per window. Now bounded: 30 days, 10,000 entries | Window titles, and **full Chrome tab URLs including query strings** — session tokens, doc IDs, search terms |
| `…/Application Support/io.github.tiagowright.pika/learned.json` | `{decayedAt, counts}`: normalised query → target key → count. Now bounded: 2% daily decay, 500 queries | Queries you have typed, and what they resolved to |
| `…/Application Support/io.github.tiagowright.pika/state.json` | onboarding progress, skipped items, last Chrome Automation answer | Nothing sensitive |
| `…/Caches/io.github.tiagowright.pika/icons/<bundleID>.png` | rasterised icons | The list of apps you run, from the filenames alone |
| `~/.config/pika/config.toml` | settings | Nothing sensitive |

### 5.2 What encryption buys, and what it does not

| Who | Does app-level encryption help? |
|---|---|
| Someone who steals the powered-off Mac | No — **FileVault** already answers this completely, and Pika cannot do better. |
| Someone at your unlocked machine | No. They can press Ctrl+Space and read the same data live. |
| Another process running as you — a sync client, a backup agent, malware, an agent with filesystem access | **Yes, this is the only real case.** Today any of them can `cat mru.json`. |
| Cloud backup, Time Machine, a screenshare, an accidental commit | Yes, partially. Exclusion and minimisation help as much. |

The honest constraint: Pika launches at login and must decrypt
unattended, with no user interaction. So the key must be reachable by
Pika without a password — which means it is reachable by anything that
can convincingly *be* Pika. This is a meaningful bar, not an absolute
one, and the README must not oversell it.

### 5.3 Options, cheapest first

**Option 0 — Store less. (Blocker.)** The strongest fix, and it needs no
key management. `TargetID.tab` uses the raw URL as its discriminator, so
full URLs land in `mru.json` forever. Replace it with a salted
`SHA-256` of the URL (salt generated once, kept in the support dir) or
with `host + path`-without-query. Matching never reads the
discriminator — it matches on `haystack`, built from app name and title —
so this costs nothing at runtime. Cap the length of stored queries in
`learned.json`. Add a `version` field to both files and drop the file on
mismatch, since this invalidates existing data. Roughly 30 lines.

**Option 1 — Permissions and exclusions. (Blocker.)** Create the support
directory `0700` and write both files `0600` (today they inherit the
umask). Set the Time Machine exclusion xattr on the cache directory.
Roughly 10 lines, no downside.

**Option 2 — Lean on FileVault. (Blocker: documentation only.)** State in
the README that data at rest is protected by FileVault, and that Pika
does not attempt to substitute for it. Zero code.

**Option 3 — AES-GCM with a key in the login keychain. (Optional; see
Q13.)** The only option that defends against another process running as
you. What it takes:

1. **Key.** `SymmetricKey(size: .bits256)` generated on first run, stored
   as a generic password item (service `io.github.tiagowright.pika`, account
   `datastore-key`) with `kSecAttrAccessibleAfterFirstUnlock`. Created by
   a signed app, the item's ACL binds to Pika's code signature.
2. **Write path.** `AES.GCM.seal(json, using: key).combined` written to
   `mru.enc` / `learned.enc`. Both stores already debounce saves onto a
   utility queue and write atomically, so nothing on the hot path
   changes. The files are tens of kilobytes; the cost is microseconds.
3. **Read path.** Decrypt at launch. On any failure — wrong key, corrupt
   file, missing keychain item — treat the store as **empty and rebuild**.
   Both stores are lossy by nature (recency and learned counts
   regenerate through use), which is what makes this safe; never
   encrypt something here that cannot be thrown away.
4. **Migration.** On first encrypted launch, read plaintext, write
   ciphertext, delete the plaintext. Do not claim the old blocks are
   gone from the SSD — they may not be.
5. **The real cost: the code signature.** The keychain ACL keys off the
   signature, exactly as the TCC grant does. Every ad-hoc rebuild
   produces a different identity, so a contributor gets a *"Pika wants to
   use your confidential information stored in your keychain"* dialog
   after every `./build.sh` — the same trap as §2.2, with a scarier
   dialog. This is the strongest argument for not making it the default
   in a build-from-source project.
6. **Scope.** Not the icon cache — encrypting PNG bytes while the
   filenames are bundle IDs protects nothing. Hash the filenames instead
   if that matters (**Q14**).
7. **Config.** `[privacy] encrypt_local_data = true|false`, and the
   README says which builds default to which.

Roughly 120 lines plus the migration and the failure paths.

**Option 4 — Per-file data protection classes.** Not available on macOS
in any form that would help. `NSFileProtection…` is an iOS API. Rejected.

### 5.4 Recommendation

Ship **0 + 1 + 2** as blockers and document the result precisely in §4.5.
Together they remove the genuinely dangerous data (full tab URLs), close
the casual-read hole, and make no promise the app cannot keep. Option 3
is specified above so it can land in v1.1 without redesign — or in v1 if
**Q13** says so.

---

## 6. Repository contents

| # | File | Must contain |
|---|---|---|
| 6.1 | 🟡 **Partly done** (2026-09-21). `README.md` covers what it is, requirements, build/install, the signing trap, a permission table, the keys, the `Ctrl+Space` collision, an annotated config (flagging `theme`/`font` as not yet read), the privacy disclosure, uninstall, known rough edges, and the as-is statement. Since 2026-09-29 it also covers the menu bar item and Settings, first-run setup, theme switching, data retention, and running the tests. **Still missing:** a screenshot or GIF, the measured latencies (`TK ms`), and the notarized-download path (§3). |
| 6.2 | ✅ **Done** (2026-09-21). `LICENSE` — MIT, Tiago Wright, 2026. |
| 6.3 | ✅ **Done** (2026-09-21). `THIRD-PARTY.md` carries both notices and the README links it. The full OFL 1.1 text is at `Sources/Pika/Resources/JetBrainsMono-OFL.txt`, and `Package.swift` copies it into the `.app` beside the font so the licence travels with every binary. Catppuccin's MIT notice is reproduced in full; the ten Mocha values in `Theme.swift` were checked against `catppuccin/palette` and all ten match. Latte falls under the same notice when §4.4 lands. |
| 6.4 | `CHANGELOG.md` | *Nice to have* at v1, but cheap to start and annoying to reconstruct later. |
| 6.5 | Issue template | One template that says support is best-effort and asks for macOS version, Pika version, and `log show --predicate 'subsystem == "io.github.tiagowright.pika"'` output — which is only a safe thing to ask for once §4.5's logging fix lands. |
| 6.6 | `requirements/` | Keep `UX.md` and `TECHNICAL.md` public — they are the most persuasive thing in the repo. Sweep them for anything you would not post: they currently reference your machine's specifics, and `TECHNICAL.md` §16 reads as open questions rather than shipped decisions. Resolve or reframe §16.1 (distribution — now answered here), §16.2 (multi-monitor), §16.4 (Ghostty titles). `UX.md` §10 is superseded by §4.3 above and should point at it. |
| 6.7 | ✅ **Verified** (2026-09-21). `git log --all --diff-filter=A` lists only source, docs, icon, font and scripts as ever added — no `.DS_Store`, no `Pika.app`, no `.build`, no store files. `.gitignore` additionally covers `.signing-identity`. No emails, tokens or home paths in any tracked file, and `AppIcon.svg` carries no authorship metadata. |
| 6.8 | 🟡 **Half done** (2026-09-21). Icon provenance is now stated in `THIRD-PARTY.md`: `AppIcon.svg` is an original design, MIT with the project. **The name check found a conflict:** `superhighfives/pika` is an open-source macOS colour picker with ~2.6k stars — same platform, same "small macOS utility" category, same name. Not necessarily a trademark problem, but a real discoverability and confusion one. Decide before the repo goes public, because a rename moves the bundle identifier again. |

---

## 7. Correctness before strangers run it

| # | Requirement |
|---|---|
| 7.1 | **Private API fallback.** `PrivateAX.swift` declares `_AXUIElementGetWindow` via `@_silgen_name`. `TECHNICAL.md` §13 promises to "feature-detect; degrade to (pid, title) matching" — that fallback is **not implemented**. The symbol resolving is a link-time assumption: if it ever disappears, Pika does not degrade, it fails to launch. At minimum, verify behaviour when it is absent and document the risk in the README. |
| 7.2 | **A smoke test in CI.** GitHub Actions on `macos-latest` running `swift build -c release`, `./build.sh release` (ad-hoc signed), and `swift test`. There is now a Swift Testing suite (config parsing and writing, the file watcher, theme contrast floors, shortcut clashes, state and history trimming). With Command Line Tools alone, `swift test` intermittently fails with "plugin for module 'TestingMacros' not found"; CI should use a full Xcode toolchain, where it is reliable. |
| 7.3 | **A clean-machine run.** Install the notarized artifact on a Mac (or a fresh user account) that has never had Pika, with no Accessibility grant and no `~/.config/pika`, and walk the whole first-run path — including **denying** Accessibility to reach the checklist's troubleshooting, recovering via Run Setup Again (§4.1.4), and denying Chrome Automation. This is the one test that catches what a checklist cannot. |
| 7.4 | **A denied-then-recovered run.** Specifically verify that `tccutil reset` (or whatever §4.1.5 concludes) genuinely brings the system prompt back on the shipping macOS version. The entire recovery story in §4.1 and the checklist's troubleshooting rests on that being true. Also exercise the Chrome denied → granted path, which `ChromeTabSource.permissionGranted()` handles but no one has run. |

---

## 8. Definition of done

1. A fresh `git clone` on another Mac runs `./build.sh` successfully with
   no Apple Developer account and no keychain setup.
2. The GitHub release page offers a notarized artifact that opens by
   double-click with no Gatekeeper dialog and no `xattr` incantation.
3. A new user can: grant Accessibility from a prompt that explains
   itself, recover from denying it *without reinstalling*, see rows on
   first hotkey press *or* a clear message saying why not, change the
   hotkey, switch to Latte, quit the app, and uninstall it completely —
   each without reading the source.
4. The README answers, above the fold, "what does this read and where
   does it send it": everything, and nowhere — and the "what it writes
   down" answer matches what the code actually writes, after §5.

---

## 9. Decisions I need from you

**Q1–Q11 are decided** (2026-09-28/29; the questions are kept below for
the reasoning). **Q12–Q14 are still open.**

| # | Decision |
|---|---|
| Q1 | Closing Setup without Accessibility leaves Pika running, with the menu bar badge as the way back; it doesn't quit. |
| Q2 | Not pre-checked. Start at login is a checklist row with a prominent Turn On and a Skip; never silent. |
| Q3 | Full activation for Setup and Settings: Pika becomes a regular app (Dock, ⌘Tab) while they're open, and activates outright. |
| Q4 | Done finishes without pressing the hotkey; pressing it also finishes and opens the switcher. |
| Q5 | Chrome is a checklist row with its explanation on screen; Allow… brings up Apple's dialog in context. |
| Q6 | Run Setup Again always starts at Welcome; the checklist shows what's already done. |
| Q7 | 20 seconds. "Listed but switched off" can't be detected without reading TCC.db, so there's no immediate trigger. |
| Q8 | Yes: a hotkey recorder in Settings → General, and inline in the checklist when the hotkey has a problem. |
| Q9 | (a): Pika edits the one line in `config.toml`, keeping comments and order. |
| Q10 | The `onboardingVersion` mechanism is in place; highlighting only the new rows waits for a second version. |
| Q11 | Yes, and `auto` is the default. |


**Onboarding (§4.3)**

- ✅ **Q1 — `esc` at the permission wall.** Quit Pika outright, or leave it
  running headless so the user can grant later and press the hotkey?
  Quitting is honest; staying resident means a user who never grants has
  a process they cannot see. *Recommendation: quit, and say so on the
  screen.*
- ✅ **Q2 — Launch at login default.** Pre-checked or unchecked on O4? A
  login-at-launch switcher is the normal expectation, but pre-checking
  is a soft version of the silent registration we are removing.
  *Recommendation: pre-checked, visible, one keystroke to clear.*
- ✅ **Q3 — Focus.** The main panel is a `.nonactivatingPanel` that never
  steals focus. Onboarding needs real key focus and sends the user to
  System Settings and back. Accept full activation for onboarding only,
  or keep it non-activating and lose the app-switch affordances?
- ✅ **Q4 — Is O4 dismissible?** Does the user have to press the hotkey once
  before onboarding closes ("you have now used the product"), or does
  Enter close it regardless?
- ✅ **Q5 — Chrome pre-notice.** Before the first Apple Event, does Pika
  show one line ("reading Chrome tabs will ask for Automation next"), or
  let Apple's dialog arrive cold? *Recommendation: one line — an
  unexplained Automation prompt is the second-scariest moment in the
  flow.*
- ✅ **Q6 — Re-run scope (§4.1.4).** Does "Run first-run setup again"
  restart from O1 always, or jump to the first unsatisfied step?
- ✅ **Q7 — O2 → O3 timeout.** How long in the waiting state before
  troubleshooting appears? *Recommendation: 20 seconds, or immediately
  if Pika is listed-but-off.*
- ✅ **Q8 — Inline hotkey capture.** If `Ctrl+Space` is taken, does O4 offer
  to capture a replacement keystroke (needs no extra permission, but does
  need the config writer in Q9), or just point at `config.toml`?
- ✅ **Q9 — Who owns `config.toml`?** The menu's theme switcher, the
  launch-at-login state, and Q8's hotkey capture all need to persist a
  user choice. Options: (a) Pika surgically rewrites the single line in
  `config.toml`, preserving the user's comments and ordering — real work,
  but the file stays the one source of truth; (b) menu choices live in
  `state.json` and `config.toml` wins when it sets a key — less work,
  but "I chose Latte in the menu and it snapped back after editing my
  config" is a confusing bug report. *Recommendation: (a).*
- ✅ **Q10 — Onboarding for upgraders.** Someone on v1 who already granted
  everything installs v1.1, which wants a new permission. Re-run only the
  new step (the `onboardingVersion` design above), or never re-run and
  handle it from the menu?

**Theme (§4.4)**

- ✅ **Q11 — Is there a "Follow system" mode in v1?** It means observing
  `NSApp.effectiveAppearance` and repainting on change, and a third
  `theme = "auto"` value. *Recommendation: yes — a light-mode user who
  installs Pika and gets a dark panel has no idea the option exists, and
  Auto makes the feature discover itself.*

**Permissions (§4.1)**

- **Q12 — May Pika run `tccutil` on itself?** Needs a five-minute test on
  the shipping macOS. If it works, "Reset and relaunch" is one click. If
  it does not, the menu shows a copyable command. Either is fine; the
  requirement is not shipping a button that appears to work and does not.

**Data at rest (§5)**

- **Q13 — Does Option 3 (AES-GCM + keychain) ship in v1?** The cost is
  ~120 lines and a keychain prompt for every contributor who rebuilds
  ad-hoc. The benefit is real but narrow. *Recommendation: no — ship
  0+1+2, document honestly, revisit in v1.1.*
- **Q14 — Icon cache filenames.** Hash the bundle IDs so
  `~/Library/Caches/io.github.tiagowright.pika/icons/` stops being a list of your
  applications, or leave it and disclose it? *Recommendation: leave it,
  disclose it — it is low value and the cache is a debugging aid.*

---

## 10. Explicitly deferred

Not blockers. Listed so they are decisions rather than oversights.

- Automatic updates (Sparkle). Manual download is acceptable at v1.
- App Store distribution — ruled out by `_AXUIElementGetWindow` anyway.
- A test suite beyond the CI build (`FuzzyMatcher` is the one piece with
  a clean, pure interface worth unit-testing when the mood strikes).
- Hiding the menu bar icon. Reopening Pika.app now opens Settings, which
  is the second way in this needed; what's left is the setting itself.
- The other Catppuccin flavours (Frappé, Macchiato) and arbitrary
  palettes from a `[colors]` table in `config.toml`. Mocha and Latte
  cover dark and light; the token layer already makes the rest cheap.
- Intel / `x86_64` support and a universal binary.
- Localisation.
- Non-Chrome browsers, and everything else in `UX.md` §11.
- `TECHNICAL.md` §16.2 (multi-monitor panel placement) and §16.4
  (Ghostty title rewriting) — ship the current behaviour, document it.
