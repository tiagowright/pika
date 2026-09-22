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

Everything here is a blocker unless marked *Nice to have*. Anything not
listed is explicitly deferred — see §10. Open decisions are collected in
§9; the body references them as **Q1**…**Q14**.

---

## 1. Why this list exists

Pika is unusually demanding of a new user's trust. It is an invisible
background agent, it asks for Accessibility — the most powerful
permission macOS grants — it reads every window title on the machine and
every Chrome tab title and URL, it registers itself to launch at login,
and it currently offers no way to quit or uninstall it. Each of those is
defensible. None of them is currently *disclosed*, and a public repo
turns each one into a reason for someone to close the tab.

The other half of the list is mechanical: the repo does not build for
anyone but you.

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

Pika is `LSUIElement` with `.accessory` activation policy: no Dock icon,
no menu bar presence, no quit command. Once installed it can only be
stopped from Activity Monitor, and `AppDelegate.registerAsLoginItem()`
silently calls `SMAppService.register()` on first launch, so it comes
back at every login.

An `NSStatusItem` answers this, and — now that permissions (§4.3) and
themes (§4.4) both need a re-entry point — it is the only place those can
live. It ships **visible by default in v1**; an option to hide it is
deferred (§10) precisely because it is the only way back into the
permission flow for a user who denied.

**Menu contents.** Everything below is a blocker unless marked.

```
  Pika 0.1.0                                  (disabled, version from 3.4)
  ────────────────────────────────────────
  Accessibility          ✓ granted           (live, disabled row)
  Chrome Automation      ✗ denied            (live, disabled row)
  Open Accessibility Settings…
  Open Automation Settings…
  Run first-run setup again…
  Reset permissions…                          (see below)
  ────────────────────────────────────────
  Theme                ▸  ✓ Mocha (dark)
                          Latte (light)
                          Follow system        (see Q11)
  ────────────────────────────────────────
  Open config…                                 (~/.config/pika/config.toml)
  Reload config
  Launch at login        ✓                     (SMAppService.mainApp.status)
  ────────────────────────────────────────
  Forget learned queries…                      (LearnedStore.forgetAll, exists)
  Open data folder…                            (Nice to have)
  ────────────────────────────────────────
  Quit Pika
```

| # | Requirement |
|---|---|
| 4.1.1 | Status item uses a **template** image (monochrome, `isTemplate = true`) so it reads correctly in both menu bar appearances. The full-colour `AppIcon.svg` cannot be used as-is. |
| 4.1.2 | Permission rows reflect live state, recomputed each time the menu opens: `AXIsProcessTrusted()` for Accessibility, and for Automation the last Apple Event result from `ChromeTabSource` (`errAEEventNotPermitted`, `-1743`) — not a guess. A third state, "not yet asked", is distinct from "denied" and must be shown as such. |
| 4.1.3 | **Open Accessibility Settings…** opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`; **Open Automation Settings…** opens `…?Privacy_Automation`. Verify both anchors resolve on the macOS version you ship against — Settings pane anchors have broken before. |
| 4.1.4 | **Run first-run setup again…** re-enters the §4.3 flow from O1, regardless of the stored onboarding state, without resetting learned data or config. This is the "I denied it and want another go" path. |
| 4.1.5 | **Reset permissions…** exists because macOS will not re-prompt once a decision is recorded: `AXIsProcessTrustedWithOptions(prompt: true)` shows nothing the second time. The only true reset is `tccutil reset Accessibility io.github.tiagowright.pika` (and `tccutil reset AppleEvents io.github.tiagowright.pika`), which requires Pika to restart afterwards. Verify whether Pika may spawn `tccutil` against its own bundle ID on the shipping macOS; if it may, offer "Reset and relaunch" behind a confirmation. If it may not, the menu item shows the exact command with a **Copy** button and a one-line explanation. Do not ship a button that silently does nothing. See **Q12**. |
| 4.1.6 | **Launch at login** is a checkbox reflecting `SMAppService.mainApp.status`, and `registerAsLoginItem()` must stop firing silently at launch — registration happens only from onboarding (§4.3, O4) or this checkbox. |
| 4.1.7 | **Reload config** re-reads `config.toml` and applies it without a relaunch. Note that `PanelController` and `AppDelegate` each call `Config.loadOrCreateDefault()` separately today; config must become a single observable source of truth before this item or the theme switcher can work. |
| 4.1.8 | An `uninstall.sh` (and a README section) that removes `/Applications/Pika.app`, unregisters the login item, deletes `~/Library/Application Support/io.github.tiagowright.pika`, `~/Library/Caches/io.github.tiagowright.pika`, and `~/.config/pika`, runs the two `tccutil reset` lines, and tells the user to check System Settings → Privacy & Security → Accessibility and → Automation by hand. |

### 4.2 Silent failures must speak

`HotKeyManager.register()` discards the `OSStatus` from
`RegisterEventHotKey`. The default hotkey is `Ctrl+Space`, which macOS
assigns to Input Sources switching out of the box —
`TECHNICAL.md` §13 lists this collision as "Low, **certain**". So the
likely first-run experience for a new user is: install, grant the
scariest permission macOS has, press the hotkey, nothing happens, no
error, no log they will find.

- Check the `OSStatus` and surface a failure the user can act on: which
  hotkey failed, that another app likely owns it, and where to change it.
  Onboarding step O4 (§4.3) is where this lands for a new user; for a
  running instance, the menu bar item shows a warning badge.
- Do the same for the other paths that currently fail into silence:
  a config file that fails to parse (today, unparseable lines are
  skipped and defaults are used with no notice) and an unparseable
  `hotkey =` value.
- **`theme =` is currently parsed by nobody.** `Config.defaultText`
  writes `theme = "catppuccin-mocha"` into every new config file and
  `Config.parse` never reads the key — so today a user who edits it sees
  no change and no message. §4.4 fixes the feature; the *reporting* rule
  is this one: an unrecognised key or value in `config.toml` must be
  reported, not ignored.

### 4.3 Onboarding (first run)

`UX.md` §10 specifies a styled first-run panel.
`AppDelegate.promptForAccessibilityAndWait()` currently fires the raw
system prompt and polls
`AXIsProcessTrusted()` every second forever, with no UI and no handling
of denial. This section replaces that with a designed flow.

**Principles.**

1. Onboarding is the only time Pika appears without being summoned.
2. It is the same panel, in the same visual language — JetBrains Mono,
   Catppuccin, 680pt wide, `❯` prompt, hard edges. Not an Aqua sheet, not
   a wizard with a Back button.
3. It asks for exactly one permission. Chrome Automation is not part of
   the wall (O5).
4. Every screen is one Enter away from the next, and `esc` always exits.
5. It ends by having the user succeed at the actual product once.

**Placement and focus.** Same rules as the main panel: the screen
containing the mouse, centred horizontally, ~38% from the top. Unlike the
main panel it must accept keyboard focus normally and may activate the
app, because the user is coming *to* it rather than passing through it
(see **Q3**).

---

**O1 — Why (shown when `!AXIsProcessTrusted()` on first launch)**

```
┌──────────────────────────────────────────────────────────────┐
│  ❯ pika                                                  1/2 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   switch windows by name. ctrl+space, two letters, enter.    │
│                                                              │
│   pika needs Accessibility to do exactly two things:         │
│     ▌ read the title of each open window                     │
│     ▌ raise the window you pick                              │
│                                                              │
│   it never uses Screen Recording or Input Monitoring,        │
│   and nothing it reads leaves this machine.                  │
│                                                              │
│   ▌ Open System Settings          ⏎                          │
│     What pika reads                r                         │
│     Quit                          esc                        │
└──────────────────────────────────────────────────────────────┘
```

- `⏎` calls `AXIsProcessTrustedWithOptions(prompt: true)` *and* opens the
  Accessibility pane deep link, then advances to O2.
- `r` opens the README's privacy section in the browser (§4.5). The
  GitHub anchor is the canonical copy; do not duplicate the prose here.
- `esc` quits without registering a login item. See **Q1**.

**O2 — Waiting**

The same panel, body replaced:

```
   waiting for the switch to flip…

   System Settings → Privacy & Security → Accessibility → Pika

   ▌ Open System Settings again       ⏎
     Quit                            esc
```

Polling continues (the existing 1s timer is fine here — it is now
visible, which was the actual problem). On grant, advance to O4
immediately; do not require a click.

**O3 — Stuck / denied**

After `N` seconds in O2 without a grant (**Q7**), or immediately if Pika
is present in the Accessibility list but switched off, the body becomes
troubleshooting:

```
   still not granted. two things usually explain it:

   ▌ pika isn't in the list       drag Pika.app into it, or use +
   ▌ pika is in the list, off     toggle it off and on once

   if pika is greyed out or the switch won't stick, the permission
   record is stale:

     tccutil reset Accessibility io.github.tiagowright.pika        ▌ Copy

   ▌ Open System Settings          ⏎
     Reset and relaunch pika        r      (subject to 4.1.5 / Q12)
     Quit                          esc
```

This is the screen the current code does not have, and the one a
first-time user is most likely to need.

**O4 — Ready**

Reached from O2/O3 on grant, or directly at first launch when
Accessibility is already trusted (a reinstall, or a rebuild under a
stable identity) but onboarding has not been completed.

```
┌──────────────────────────────────────────────────────────────┐
│  ❯ pika                                                  2/2 │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│   granted. press ctrl+space to try it.                       │
│                                                              │
│   [✓] start pika when i log in                s              │
│   [ ] read chrome tab titles too              c              │
│                                                              │
│   pika lives in the menu bar. everything — quitting,         │
│   permissions, themes — is there.            ▌ (arrow to it) │
│                                                              │
│   ▌ Done                          ⏎                          │
└──────────────────────────────────────────────────────────────┘
```

- **Launch at login is opt-in here** (§4.1.6). Default state per **Q2**.
- The Chrome checkbox is a *consent to ask*, not the permission itself.
  Ticking it means the first Apple Event may fire (O5); leaving it clear
  writes `chrome_tabs = false` (which requires the config writer — **Q9**).
- If `RegisterEventHotKey` failed (§4.2), this screen says so instead of
  "press ctrl+space", names the hotkey, says another app likely owns it,
  and points at `~/.config/pika/config.toml` — or offers inline capture
  of a replacement (**Q8**).
- Pressing the hotkey here dismisses onboarding and shows the real panel
  (**Q4**).

**O5 — Chrome Automation, later and in context**

Not part of the wall. It fires on the first Chrome poll after onboarding
completes, and only if the O4 checkbox was ticked. Apple's own dialog is
what the user sees; the question is whether Pika says anything first
(**Q5**). Denial is not an error state: `ChromeTabSource` already backs
off and retries, windows are still listed by title, and the menu bar
shows Automation as denied with a way back.

**Completion state.** `~/Library/Application Support/io.github.tiagowright.pika/state.json`
holds `{ "onboardingVersion": 1, "completedAt": …, "hotkeyVerified": … }`.
Onboarding runs when the file is absent or its version is lower than the
build's (so a future release that needs a new permission can re-run just
that step), or when invoked from the menu (§4.1.4). Never otherwise.

**Non-goals.** No multi-page tour, no animation, no splash on later
launches, no "rate us", no telemetry of any step.

See **Q1**–**Q10**.

### 4.4 Catppuccin Latte (new feature)

Mocha-only is a reasonable default and a poor look on a machine in Light
Mode. Latte ships in v1, selectable from the menu (§4.1) and from
`config.toml`.

| # | Requirement |
|---|---|
| 4.4.1 | `Theme.catppuccinLatte` alongside `Theme.catppuccinMocha`, same ten tokens. Starting values: `bg` `#eff1f5` (base), `bg_input` `#e6e9ef` (mantle), `border` `#bcc0cc` (surface1), `fg` `#4c4f69` (text), `fg_dim` `#8c8fa1` (overlay1), `fg_muted` `#9ca0b0` (overlay0), `accent` `#8839ef` (mauve), `accent_alt` `#1e66f5` (blue), `sel_bg` `#ccd0da` (surface0), `warn` `#df8e1d` (yellow). Verify every hex against `catppuccin/catppuccin` before shipping — `UX.md` §7 carries the same warning about the Mocha set, and it has not been discharged. |
| 4.4.2 | Re-check the tokens that were tuned for a dark panel. On Latte, `fg_dim`/`fg_muted` must be *darker* than `fg`'s surroundings rather than lighter, the 1pt `border` at `#bcc0cc` can disappear against a light window behind it (consider crust `#dce0e8` or a heavier border in light mode), and `warn` yellow on a light background is the weakest contrast pair in the palette. Check the matched-character accent against `sel_bg` too — that pairing carries the whole fuzzy-match affordance. |
| 4.4.3 | `Config.parse` must actually read `[appearance] theme`, accepting `catppuccin-mocha`, `catppuccin-latte`, and (per **Q11**) `auto`. Today the key is written into every default config and silently ignored — see §4.2. An unknown value must be reported, not defaulted away. |
| 4.4.4 | Menu: a **Theme** submenu with radio-state items. Selecting one applies it immediately and persists it (**Q9** decides where). |
| 4.4.5 | Runtime switching without a relaunch. `PanelController` captures `Config` at `init` and `PikaView` holds it as a `let`; the panel is prewarmed once and must **not** be rebuilt (TECHNICAL.md §9: a cold `orderFront` costs ~150ms vs ~3ms warm). Make the config/theme a mutable property with an `apply(_:)` that updates `view.layer.borderColor` and calls `needsDisplay = true`. Verify the panel is invisible when the switch happens, or that the repaint is clean if it is not. |
| 4.4.6 | `Config.defaultText` documents both values in the comment on the `theme` line. |
| 4.4.7 | `UX.md` §7 gains the Latte column, and `THIRD-PARTY` attribution (§6.3) covers the Latte palette under the same Catppuccin MIT licence. |

### 4.5 Privacy and permissions, in writing — in the README

**No `PRIVACY.md`.** A separate file is one more click away from the
person deciding whether to trust this, and it will drift. The disclosure
is a README section, linked from the top, and it is the same text O1
points at (`r`).

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
- How to see and delete the data: the paths above, the **Forget learned
  queries…** menu item, and `uninstall.sh` (§4.1.8).

---

## 5. Data at rest — what encryption would actually take

### 5.1 What is on disk today

| Path | Contents | Worst case if read |
|---|---|---|
| `…/Application Support/io.github.tiagowright.pika/mru.json` | `bundleID\0discriminator` → timestamp, plus a `bundleID\0title:<title>` fallback key per window | Window titles, and **full Chrome tab URLs including query strings** — session tokens, doc IDs, search terms |
| `…/Application Support/io.github.tiagowright.pika/learned.json` | normalised query → target key → count | Every query you have typed, and what it resolved to |
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
| 6.1 | 🟡 **Partly done** (2026-09-21). `README.md` covers what it is, requirements, build/install, the signing trap, a permission table, the keys, the `Ctrl+Space` collision, an annotated config (flagging `theme`/`font` as not yet read), the privacy disclosure, uninstall, known rough edges, and the as-is statement. **Still missing:** a screenshot or GIF, the notarized-download path (§3), the menu bar item (§4.1), and theme switching (§4.4). |
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
| 7.2 | **A smoke test in CI.** GitHub Actions on `macos-latest` running `swift build -c release` and `./build.sh release` (ad-hoc signed). You have no test suite and are not obliged to write one, but a PR that does not compile should not need you to notice it by hand. |
| 7.3 | **A clean-machine run.** Install the notarized artifact on a Mac (or a fresh user account) that has never had Pika, with no Accessibility grant and no `~/.config/pika`, and walk the whole first-run path — including **denying** Accessibility to reach O3, recovering from the menu (§4.1.4), and denying Chrome Automation. This is the one test that catches what a checklist cannot. |
| 7.4 | **A denied-then-recovered run.** Specifically verify that `tccutil reset` (or whatever §4.1.5 concludes) genuinely brings the system prompt back on the shipping macOS version. The entire recovery story in §4.1 and O3 rests on that being true. |

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

**Onboarding (§4.3)**

- **Q1 — `esc` at the permission wall.** Quit Pika outright, or leave it
  running headless so the user can grant later and press the hotkey?
  Quitting is honest; staying resident means a user who never grants has
  a process they cannot see. *Recommendation: quit, and say so on the
  screen.*
- **Q2 — Launch at login default.** Pre-checked or unchecked on O4? A
  login-at-launch switcher is the normal expectation, but pre-checking
  is a soft version of the silent registration we are removing.
  *Recommendation: pre-checked, visible, one keystroke to clear.*
- **Q3 — Focus.** The main panel is a `.nonactivatingPanel` that never
  steals focus. Onboarding needs real key focus and sends the user to
  System Settings and back. Accept full activation for onboarding only,
  or keep it non-activating and lose the app-switch affordances?
- **Q4 — Is O4 dismissible?** Does the user have to press the hotkey once
  before onboarding closes ("you have now used the product"), or does
  Enter close it regardless?
- **Q5 — Chrome pre-notice.** Before the first Apple Event, does Pika
  show one line ("reading Chrome tabs will ask for Automation next"), or
  let Apple's dialog arrive cold? *Recommendation: one line — an
  unexplained Automation prompt is the second-scariest moment in the
  flow.*
- **Q6 — Re-run scope (§4.1.4).** Does "Run first-run setup again"
  restart from O1 always, or jump to the first unsatisfied step?
- **Q7 — O2 → O3 timeout.** How long in the waiting state before
  troubleshooting appears? *Recommendation: 20 seconds, or immediately
  if Pika is listed-but-off.*
- **Q8 — Inline hotkey capture.** If `Ctrl+Space` is taken, does O4 offer
  to capture a replacement keystroke (needs no extra permission, but does
  need the config writer in Q9), or just point at `config.toml`?
- **Q9 — Who owns `config.toml`?** The menu's theme switcher, the
  launch-at-login state, and Q8's hotkey capture all need to persist a
  user choice. Options: (a) Pika surgically rewrites the single line in
  `config.toml`, preserving the user's comments and ordering — real work,
  but the file stays the one source of truth; (b) menu choices live in
  `state.json` and `config.toml` wins when it sets a key — less work,
  but "I chose Latte in the menu and it snapped back after editing my
  config" is a confusing bug report. *Recommendation: (a).*
- **Q10 — Onboarding for upgraders.** Someone on v1 who already granted
  everything installs v1.1, which wants a new permission. Re-run only the
  new step (the `onboardingVersion` design above), or never re-run and
  handle it from the menu?

**Theme (§4.4)**

- **Q11 — Is there a "Follow system" mode in v1?** It means observing
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
- Hiding the menu bar icon. It is the only re-entry point for the
  permission flow (§4.1), so an option to hide it needs a second path
  (a CLI, or a URL scheme) before it can exist.
- The other Catppuccin flavours (Frappé, Macchiato) and arbitrary
  palettes from a `[colors]` table in `config.toml`. Mocha and Latte
  cover dark and light; the token layer already makes the rest cheap.
- A preferences window. The menu plus `config.toml` is the v1 surface.
- Intel / `x86_64` support and a universal binary.
- Localisation.
- Non-Chrome browsers, and everything else in `UX.md` §11.
- `TECHNICAL.md` §16.2 (multi-monitor panel placement) and §16.4
  (Ghostty title rewriting) — ship the current behaviour, document it.
