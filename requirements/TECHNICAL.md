# Pika — Technical Implementation Outline

Target: macOS 26 (Tahoe), Apple Silicon. Swift 6.4. Companion to `UX.md`.

---

## 0. Measured baseline

I measured the risky operations on this machine (macOS 26.6.2, 16 foreground apps, 94 windows, 16 Chrome tabs across 16 Chrome windows) before designing anything. These numbers drove every decision below.

| Operation | Cold | Warm | Verdict |
|---|---|---|---|
| `CGWindowListCopyWindowInfo` (94 windows) | 42 ms | **1.8–2.7 ms** | Fine on the hot path if needed. |
| `kCGWindowName` (window titles) | — | — | **Returns empty without Screen Recording permission.** Do not use. |
| `NSWorkspace.runningApplications` | 7 ms | <1 ms | Fine. |
| AX sweep, **serial**, 16 apps | **299 ms** | — | ✗ Never on the hot path. |
| AX sweep, **parallel**, 16 apps | **136 ms** | see note | ✗ Never on the hot path, even parallel. |
| Chrome tabs, **naive** nested-loop AppleScript | 4,260 ms | 830 ms | ✗✗ Never write it this way. |
| Chrome tabs, **bulk** `title of tabs of every window` | — | **120 ms** | Background, but cheap enough to refresh often. |
| Chrome tabs, bulk titles **+ URLs** | — | 160 ms | Same. |
| `osascript` process spawn (baseline, subtract it) | — | 50 ms | In-process AppleScript avoids this → **~70 ms real work**. |
| App icons: fetch 16 `NSRunningApplication.icon` | 80 ms | 0 ms | Cache at launch. |
| App icons: rasterize 16 to 32×32 bitmaps | **323 ms** | 0 ms | Pre-rasterize at launch → **icons are free at query time. Ship them.** |

> **Caveat on the AX numbers:** these were taken with Accessibility permission *not* granted, so the calls failed fast. The cold figures are real IPC/connection-setup cost and are a **lower bound**; a permitted sweep that actually walks window lists will be slower. Re-measure once the entitlement is granted. The conclusion doesn't change — it only gets stronger.

**A 10× correction worth calling out.** My first Chrome measurement (830 ms) used the obvious nested-loop formulation — `repeat with w in windows / repeat with t in tabs of w / get title of t` — which costs one Apple Event round-trip *per tab*. The bulk form, `get title of tabs of every window`, is a **single** round-trip and costs 120 ms wall, of which ~50 ms is `osascript` process spawn that an in-process `NSAppleScript` doesn't pay. So the real figure is **~70 ms**, not 830 ms. Chrome tabs are roughly 12× cheaper than they first appeared. They still don't belong on the hot path — 70 ms is 4× the frame budget and the call can hang if Chrome is busy — but they can be refreshed aggressively in the background rather than treated as a rare expensive operation.

**Three conclusions fall out of this table:**

1. **We can avoid Screen Recording permission entirely.** Titles come from the Accessibility API, which we need anyway to raise windows. `CGWindowList` is still used for z-order, window IDs, window *existence across Spaces* (§5d), and junk filtering — all of which work without the permission. Asking for one scary permission instead of two is a real product win. The cost is paid in §5d: AX titles are Space-scoped, so titles for windows on other Spaces are as of the last visit.
2. **Nothing may be enumerated after the hotkey fires.** Not AX, not AppleScript. The answer must already be in memory.
3. **Icons cost nothing if pre-rasterized.** The 323ms is a one-time startup cost on a background queue.

---

## 1. Latency budget

| Segment | Budget | How |
|---|---|---|
| Hotkey event → our handler | < 1 ms | Carbon `RegisterEventHotKey` (kernel-dispatched, not an event tap). |
| Handler → panel visible with rows | **< 16 ms** | Pre-warmed panel + pre-computed MRU snapshot. Zero allocation, zero I/O. |
| Keystroke → repainted list | **< 8 ms** | Incremental match over a flat cache-friendly index; ≤10 rows drawn. |
| Enter → panel gone | < 2 ms | Hide first, activate after. |
| Enter → target window frontmost | < 100 ms | AX raise + `activate()`. Not on the perceived path. |
| **Total perceived (hotkey → typed → switched)** | **< 30 ms** | |

The 250ms bar is 8× this. Aiming an order of magnitude under the requirement is what leaves room for the real world — a hung app, a Space switch, a cold page-in.

---

## 2. Architecture

```
                          ┌───────────────────────────────────────┐
                          │  Pika.app  (LSUIElement, resident)    │
                          └───────────────────────────────────────┘

  ══ HOT PATH (main thread, must never block) ═════════════════════════════════

    Carbon hotkey ──▶ PanelController ──▶ NSPanel (pre-warmed, never released)
                            │                    │
                            ▼                    ▼
                      QueryEngine ◀────── ResultsView (AppKit, hand-drawn rows)
                            │
                            ▼
                    ┌───────────────┐
                    │  TargetIndex  │  ← immutable snapshot, atomically swapped
                    │  (struct-of-  │     struct-of-arrays, precomputed
                    │   arrays)     │     haystacks + bitmasks + icons
                    └───────────────┘
                            ▲
  ══ COLD PATH (background queues, may block, may fail) ══════════════════════
                            │
              ┌─────────────┼──────────────┬────────────────┐
              │             │              │                │
        WindowSource   TabSource      IconCache        MRUStore
       (AX + CGWindow) (Chrome AS)   (pre-raster)    (persisted)
              │             │
        AXObserver     poll on Chrome
        per-app         focus change
        (event-driven)  + idle timer
```

The single most important structural rule: **the hot path reads an immutable snapshot and nothing else.** Background sources build a new snapshot off-thread and swap the pointer. There are no locks on the hot path, no lazy loading, no "fetch if stale".

---

## 3. Process and lifecycle

- `LSUIElement = true` — no Dock icon, no menu bar item by default.
- Launch at login via `SMAppService.mainApp.register()`.
- **Disable App Nap.** A resident agent that sits idle gets throttled, and the first hotkey after a quiet period would be visibly slow. Hold a persistent activity:
  ```swift
  ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
      reason: "Instant window switching")
  ```
  This is easy to forget and produces exactly the "it's fast except the first time" bug.
- UI work on the main thread at `.userInteractive` QoS. All sources at `.utility`.

---

## 4. The index

```swift
// Struct-of-arrays, not array-of-structs. Matching touches only `haystack`,
// `bounds`, and `firstLetterMask` — keeping those contiguous means the hot
// loop stays in L1 instead of striding over icons and window handles.
struct TargetIndex {
    // matching-hot fields
    var haystack:        [UInt8]      // all targets' folded text, concatenated
    var span:            [Range<Int>] // slice of `haystack` per target
    var appNameLength:   [UInt16]     // where the app name ends within the span
    var wordStartBits:   [UInt64]     // bitmask of word-start offsets (first 64 chars)
    var firstLetterMask: [UInt32]     // bloom of letters present → O(1) reject
    var mruRank:         [UInt32]     // 0 = current window

    // presentation-cold fields (parallel arrays, touched only for visible rows)
    var display:         [DisplayRow] // app name, title, icon ref, recency string
    var handle:          [TargetHandle] // AXUIElement + pid + CGWindowID + tab id
}
```

**Text normalisation happens once, at index build time**, never per keystroke: lowercase, strip diacritics, fold to ASCII where possible, collapse whitespace. The query is normalised the same way, once per keystroke.

`firstLetterMask` is a 26-bit set of which a–z letters appear in the target. Before running the scorer, `if query.mask & ~target.mask != 0 { reject }`. With ~150 targets this eliminates most candidates in a few nanoseconds each.

**Snapshot swap:** the index is a class instance held in an `AtomicReference`-style box; sources build a fresh one and CAS it in. Readers never see a torn state and never take a lock.

---

## 5. Sources

### 5a. Windows — Accessibility API (primary)

The index is **event-driven, not polled.** By the time the hotkey fires, it's already correct.

- `NSWorkspace.shared.notificationCenter`: `didLaunchApplication`, `didTerminateApplication`, `didActivateApplication`, `didDeactivateApplication`.
- Per running app, an `AXObserver` on the application element for:
  `kAXWindowCreatedNotification`, `kAXUIElementDestroyedNotification`,
  `kAXFocusedWindowChangedNotification`, `kAXTitleChangedNotification`,
  `kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification`.
- A **debounced full re-sweep** as a safety net (AX notifications are not perfectly reliable): on a background queue, ~every 5s while idle, and immediately when the panel opens (results merge in and the list re-sorts without moving the selection).

Three non-obvious requirements:

1. **Warm and retain the AX connections.** Measured: 136ms cold for a parallel sweep across 16 apps, essentially all of it connection setup. Create `AXUIElementCreateApplication(pid)` once per app when the app launches (or at Pika startup) and **hold the reference for the app's lifetime**. Never recreate it per query.
2. **Set a messaging timeout on every element.**
   ```swift
   AXUIElementSetMessagingTimeout(appElement, 0.15)
   ```
   Without this, a beachballing app blocks the AX call *indefinitely*. This is the number-one way window switchers hang.
3. **One serial queue per target app.** AX calls to a given app serialise anyway; giving each app its own queue means a slow app degrades only its own rows. A global concurrent queue would let one hung app exhaust the thread pool.

### 5b. Windows — `CGWindowListCopyWindowInfo` (supplement)

Fast (≈2ms warm) and gives what AX doesn't: **z-order**, `kCGWindowNumber`, on-screen state, bounds, and — critically — **windows on every Space** (§5d). Used to filter out zero-size junk windows, to decide which windows still exist, and to seed initial MRU order from z-order at startup.

Note the option flags: `.optionOnScreenOnly` narrows the list to the Space you are currently looking at. We deliberately do not pass it.

Correlating a `CGWindowID` with an `AXUIElement` requires the private-but-ubiquitous:

```swift
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ out: UnsafeMutablePointer<CGWindowID>) -> AXError
```

Every serious macOS window manager (yabai, AeroSpace, Rectangle) uses this. It has been stable for a decade but is unsupported — wrap it, feature-detect it, and degrade to title+pid matching if it ever fails. See Risks.

### 5d. Spaces — why the window cache exists

**Measured, not assumed: AX window enumeration is Space-scoped.**
`kAXWindowsAttribute` returns only the windows on the Space you are
currently looking at, and returns them with `AXError.success` — so
"you are standing on a different Space" is indistinguishable from
"this app has no windows". Swept from an empty Space, all 14 running
apps reported success with zero windows, and the index went empty.

`CGWindowListCopyWindowInfo` has the exact opposite property: it sees
every Space, but its titles need Screen Recording, which §0 exists to
avoid. So the two are split by what each is actually good for:

| Question | Source |
|---|---|
| Which windows exist? | `CGWindowList`, all Spaces, no permission |
| What is this window called? | AX, current Space only |
| How do I raise it? | A retained `AXUIElement`, valid across Spaces |

`WindowSource.windowCache` is what lets those facts be observed at
different times: keyed by `CGWindowID`, written whenever AX can see a
window, evicted when CG stops listing it (or, for minimised windows,
which can drop out of the CG list, when an `AXRole` probe returns
`.invalidUIElement`). An empty AX sweep is never treated as evidence
that windows went away.

Two consequences, both inherent:

- **A Space must be visited once per launch** before its windows are
  known. `NSWorkspace.activeSpaceDidChangeNotification` triggers an
  immediate sweep on arrival, so one visit suffices.
- **Titles for windows on other Spaces are as of the last visit.**

### 5c. Chrome tabs

**Decision: tabs are first-class rows from v1, filled in progressively.**

Cost is ~70 ms in-process for a bulk refresh of every tab in every window (see the correction in §0). That is well outside the 8 ms keystroke budget and the call can block if Chrome is busy, so it stays a background source — but it's cheap enough to run on every Chrome focus change rather than on a slow timer.

**Query formulation is the whole game here.** Always:

```applescript
tell application "Google Chrome"
    set t to title of tabs of every window
    set u to URL of tabs of every window
    set i to id of every window
    return {t, u, i}
end tell
```

Never a nested `repeat`. One round-trip returns a list-of-lists; N round-trips costs 10× more. Use in-process `NSAppleScript` (or a compiled `OSAScript` held for the process lifetime) rather than spawning `osascript`, which saves another 50 ms per call.

**Progressive fill, so a cold start is never a slow start.** The index exposes Chrome at three tiers, and the panel always renders whatever tier is currently available:

| Tier | Content | Available | Cost |
|---|---|---|---|
| **T0** | Chrome **windows only**, titled by their active tab | Immediately at launch, from the AX source | 0 ms extra |
| **T1** | Tabs of the **focused (or most recently used) Chrome window** | ~70 ms after launch | one bulk call, scoped to one window |
| **T2** | Tabs of **all remaining windows**, in window-MRU order | shortly after T1 | one bulk call |

At launch the index is populated at T0 and is fully usable — Chrome rows exist, they're just window-granular. T1 and T2 land within a few hundred milliseconds and swap in new snapshots. **If the hotkey is pressed during that window, the user sees T0 rows and never waits.** Rows appearing is a fill-in, which per `UX.md` §8 must not move the current selection.

The T1/T2 split matters for the first-run case (Automation permission prompt) and after a Chrome restart with many windows; in steady state the whole thing is one 70 ms call.

**Refresh triggers:** Chrome activates or deactivates, a Chrome window title changes (via the existing AXObserver), a Chrome window is created or destroyed, or a 5 s idle timer while Chrome is frontmost. Runs on a dedicated serial queue with a 3 s hard timeout; on timeout the previous snapshot is retained and the rows are marked stale.

Diff the result against the previous snapshot and rebuild only changed spans, so a refresh with no changes allocates nothing.

Requires the **Automation (Apple Events)** TCC permission for Chrome, prompted once. If denied, Chrome degrades permanently to T0 — which is exactly the windows-only behaviour, so nothing breaks.

**v2 — Chrome extension + native messaging host.** A ~40-line extension subscribing to `chrome.tabs.onUpdated/onCreated/onRemoved/onActivated` pushes deltas over stdio to a helper. Cost at query time and refresh time: **zero**, and no Automation prompt. Costs the user a manual extension install. Still the right long-term answer, and it generalises to Arc/Edge/Brave — but at 70 ms the v1 AppleScript path is no longer painful enough to rush it.

### 5d. Ghostty

**Good news, verified:** Ghostty responds to standard Cocoa scripting and uses **native macOS window tabbing**, so each tab is a separate `NSWindow`. `tell application "Ghostty" to get name of every window` returned all 5 open tabs' titles, and `CGWindowList` independently sees 5 Ghostty windows.

**Therefore Ghostty tabs need no special code at all** — the generic AX window source already picks them up, with the working directory / running command in the title. Nothing to build.

### 5e. Slack

**Verified: Slack has no AppleScript support** (`-1728, Can't get name of every window`). It's Electron, and its channel switcher isn't a window or a tab.

Options, in order of cost:
- **v1 (recommended): window titles only.** Slack's window title already reads `#channel - Workspace`, which is exactly what you'd want to fuzzy-match anyway. Two Slack windows were present, both indexed for free by the AX source.
- v2: walk the AX tree for the sidebar's channel list. Slow (hundreds of ms), extremely fragile against Slack UI updates, and would only give you *navigable* channels rather than open windows — which is arguably out of scope per "only existing windows".

I'd recommend not building 5e's v2.

### 5f. Icons

Measured: 80ms to fetch + **323ms to rasterize** 16 icons — and then **0ms forever after**.

At launch, on a background queue:
1. `NSRunningApplication.icon` (or `NSWorkspace.icon(forFile: bundleURL.path)`).
2. Draw once into a `CGImage` at the exact display size × backing scale (32×32 @2x).
3. Cache in memory keyed by bundle identifier, and write to `~/Library/Caches/io.github.tiagowright.pika/icons/<bundleid>@2x.png` so restarts are near-instant.
4. New apps rasterize lazily in the background; rows render with a placeholder glyph until ready.

Drawing a pre-rasterized `CGImage` into a row is a single blit. **Icons are free. Ship them.**

---

## 6. Permissions

| Permission | Required? | For what | If denied |
|---|---|---|---|
| **Accessibility** | **Yes, hard** | Window titles, window enumeration, raising windows | Pika cannot function. First-run wall. |
| Automation → Google Chrome | Optional | Tab titles | Chrome windows still listed by title. |
| **Screen Recording** | **No** | — | Deliberately avoided by taking titles from AX instead of `kCGWindowName`. |
| Input Monitoring | No | — | Avoided by using Carbon `RegisterEventHotKey` rather than a `CGEventTap`. |

Getting this down to *one* prompt (plus one optional) is worth defending in code review.

---

## 7. Matching engine

**Model:** fzf-style Smith-Waterman-lite over a composite haystack of `appName + '\0' + title` (+ `'\0' + tabTitle`).

### Per keystroke

```
1. Normalise query (once).
2. Compute query first-letter mask.
3. Candidate set:
     - if the query is an extension of the previous query (one char appended),
       iterate only the previous match set  ← the big win
     - else iterate all targets
4. Reject via firstLetterMask (O(1), ~1ns).
5. Cheap greedy forward subsequence scan → reject non-matches.
6. Full scoring pass only on survivors.
7. Partial-sort top 10 (heap), not a full sort.
```

Step 3 is the key optimisation and relies on a real property: **fuzzy subsequence matching is monotone.** If `zp` doesn't match a target, `zpi` cannot. So the candidate set only ever shrinks as you type. Typing is therefore *cheaper* per keystroke the more you've typed, and the expensive case is the single first character — which is exactly when the panel has just opened and there's slack.

### Scoring

```
score = Σ per-matched-char bonuses − gap penalties + field weights + recency
```

| Component | Weight (starting point, all config-tunable) |
|---|---|
| Match at app-name start | **+120** |
| Match at word start in title (after ` -_/.—:`, or camelCase) | **+80** |
| Match anywhere in app name | +40 |
| Consecutive with previous match | +50 |
| Exact case match | +10 |
| Gap penalty | −5 per skipped char, capped at −40 |
| Leading-gap penalty | −3 per char before the first match |
| Whole query is a prefix of the app name | +100 |
| Recency | `+recency_weight × exp(−mruRank / 8)` |

That table is what makes `zp` → *Zed / pika* work: `z` scores +120 (app-name start) and `p` scores +80 (word start in title), for 200 before recency — while a target where both letters land mid-word scores near zero.

**Recency is bounded on purpose.** With `recency_weight = 40`, recency can never overcome a word-start bonus. It only reorders matches of comparable quality — which is the behaviour described in the brief ("*tend to* get ranked higher").

**Scoring is not the bottleneck.** With ~150 targets and ~50-char haystacks, a full unoptimised pass is on the order of tens of microseconds. The optimisations above exist to keep it that way at 500+ targets (many Chrome tabs), and to leave the frame budget for drawing.

### Learned selections (confirmed for v1)

Persist `(normalized query → target key) → count` in `~/Library/Application Support/io.github.tiagowright.pika/learned.json`.

- **Target key** must survive restarts and title changes, so it is `(bundleID, windowIndexWithinApp)` for windows and `(bundleID, url)` for tabs — never a `CGWindowID`.
- On each query, look up the exact query and each of its prefixes; add `learn_weight × log2(1 + count)`, capped so a single stale learned entry can't outrank a strong fresh match.
- Decay: multiply all counts by 0.98 on each write, and drop entries below 0.1. This lets the model forget projects you've moved on from without any explicit cleanup.
- One dictionary lookup per query, loaded into memory at launch — **no file I/O on the hot path** (§12).
- Config: `ranking.learning = true`, `ranking.learn_weight = 60`. A `pika --forget` command clears it.

---

## 8. MRU tracking

- A monotonic counter; each window records `lastFocusedAt`.
- Updated on `NSWorkspace.didActivateApplication` (app level) and `kAXFocusedWindowChangedNotification` (window level).
- **Pika's own PID is excluded** — the panel taking key focus must never perturb the stack.
- Persisted to `~/Library/Application Support/io.github.tiagowright.pika/mru.json` on a debounce so ordering survives a restart; entries are matched back by `(bundleID, title)` since `CGWindowID`s don't survive.
- **Decided:** the empty-query list is MRU with the current window **omitted entirely** — not dimmed, not last. So `list[0]` is unambiguously the previous window, and there is no row whose selection is a no-op. The current window reappears in the list as soon as a query is typed (it can still be a legitimate fuzzy match).

---

## 9. Rendering

**Recommendation: AppKit, hand-drawn rows. Not SwiftUI.**

SwiftUI's diffing and layout costs are real and, more importantly, *not bounded by anything you control* — a keystroke-driven list is exactly the workload where its update cost is unpredictable. For a 10-row fixed-height list with a fixed-width font, a hand-rolled `NSView` with `draw(_:)` using CoreText is a few hundred lines and gives a hard guarantee.

- One `NSView` for the whole list; draw all 10 rows in a single `draw(_:)`. No per-row views, no `NSTableView` reuse machinery to reason about.
- `CTLine` objects for app names are cached per app (they never change).
- Only the highlight ranges change per keystroke — build the `CFAttributedString` for the ≤10 visible titles per frame, which is microseconds.
- Constant row height → scrolling is arithmetic.
- Panel is `NSPanel(styleMask: [.nonactivatingPanel, .borderless])`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isReleasedWhenClosed = false`.
- **Pre-warm it at launch:** create, lay out, force one `display()` offscreen, then `orderOut`. Showing it later is `orderFrontRegardless()` + `makeKey()`. This converts a ~150ms first-show into a ~3ms one, and is the single largest hot-path win available.

SwiftUI is fine later for a preferences window, where latency doesn't matter.

---

## 10. Activation

Order matters, and the naive order has a race where the app comes forward but the wrong window is frontmost.

```swift
func activate(_ t: TargetHandle) {
    panel.orderOut(nil)                          // 1. hide FIRST — perceived latency 0
    activationQueue.async {                      // 2. never on the main thread
        if let win = t.axWindow {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: t.pid)?
            .activate(options: [])               // 3. then bring the app forward
        if let tab = t.chromeTab { selectChromeTab(tab) }  // 4. AppleScript, async
    }
}
```

Notes:
- `kAXRaiseAction` before `activate()` avoids the flash of the app's *previous* frontmost window.
- Don't pass `.activateAllWindows` — it defeats the point.
- Chrome tab selection is a separate AppleScript round-trip (~150ms) that happens *after* the window is already up, so it isn't perceived as switch latency.
- Verify the target still exists; fall back to app-level activation, then to nothing.

---

## 11. Threading and failure isolation

| Thread / queue | QoS | Work | May block? |
|---|---|---|---|
| Main | `.userInteractive` | Hotkey, panel, matching, drawing | **Never** |
| `index.build` (serial) | `.utility` | Assemble snapshots, swap pointer | Yes |
| `ax.<pid>` (serial, one per app) | `.utility` | All AX calls for one app | Yes, timeout 150ms |
| `chrome.tabs` (serial) | `.utility` | AppleScript, timeout 3s | Yes |
| `icons` (concurrent) | `.background` | Rasterize + disk cache | Yes |
| `activation` (serial) | `.userInitiated` | Raise + activate | Yes |

**Failure isolation is a design requirement, not error handling.** Every source is independently expendable: Chrome hangs → Chrome tabs go stale, everything else is unaffected. An app beachballs → its rows serve from the last known snapshot, marked dim. AX permission is revoked mid-session → detect via `AXIsProcessTrusted()` and show the first-run wall instead of an empty list.

---

## 12. Optimisation checklist

Things that must be true, gathered in one place for review:

- [ ] Pre-warmed `NSPanel`, never released, force-displayed once at launch
- [ ] Zero allocation on the empty-query path (MRU snapshot precomputed on every focus change, not on hotkey)
- [ ] AX application elements created once per app and retained
- [ ] `AXUIElementSetMessagingTimeout` on every element
- [ ] Index is an immutable snapshot, atomically swapped, never locked
- [ ] Struct-of-arrays layout; matching touches only the hot arrays
- [ ] Text normalised at index time, never per keystroke
- [ ] First-letter bitmask rejection before scoring
- [ ] Incremental candidate narrowing on query extension
- [ ] Partial sort (top-10 heap), never a full sort
- [ ] Icons pre-rasterized to exact pixel size, memory + disk cached
- [ ] No file I/O, JSON, plist, or `UserDefaults` read after launch (learned-selection map lives in memory)
- [ ] Chrome queried with bulk `of every window` form, never a nested `repeat` (10× cost)
- [ ] In-process `NSAppleScript`, never an `osascript` spawn (saves 50 ms/call)
- [ ] Chrome tiers T0→T1→T2 fill in without moving the selection
- [ ] Only ≤10 rows ever drawn or laid out
- [ ] Constant row height; no text measurement per frame
- [ ] App Nap disabled via a persistent activity
- [ ] No animation on show, hide, or selection move
- [ ] Panel hidden before activation work begins
- [ ] `os_signpost` around hotkey→first-frame and keystroke→repaint, plus a debug HUD showing live ms

---

## 13. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `_AXUIElementGetWindow` is private API | Medium | Not needed for App Store distribution (this isn't going there). Feature-detect; degrade to (pid, title) matching. |
| AX notifications are unreliable / missed | Medium | Debounced safety-net re-sweep + a sweep on panel open. |
| Real AX sweep cost is worse than the ≥136ms measured | Medium | Already assumed unusable on the hot path; the whole design is event-driven so this only affects the safety net. |
| Hung app blocks a sweep | High if unhandled | Per-app queue + 150ms messaging timeout. |
| Chrome AppleScript at 830ms | Handled | Background-only, stale-tolerant; extension in v2. |
| `Ctrl+Space` collides with Input Sources | Low, certain | Detect at first run, guide the user, offer an alternative. |
| Electron/Chrome apps toggle `AXEnhancedUserInterface` and slow down | Medium | Read-only access mostly avoids it; don't set the attribute ourselves. |
| Index grows large (many Chrome tabs) | Low | Design already handles 500+; measure at 2,000. |
| Accessibility permission is revoked by a Pika code-signature change | Medium | Stable signing identity from day one; detect and re-prompt. |

---

## 14. Build plan

| Milestone | Contents | Proves |
|---|---|---|
| **M0 — Spike** | Grant AX, re-measure the real sweep cost, verify `_AXUIElementGetWindow`, verify raise-window works across Spaces | The measurements this plan rests on |
| **M1 — Skeleton** | LSUIElement agent, Carbon hotkey, pre-warmed panel, hardcoded rows, signpost instrumentation | The <16ms hot path, end to end |
| **M2 — Index** | AX window source, `CGWindowList` supplement, AXObservers, MRU tracking | Hotkey+Enter = alt-tab |
| **M3 — Matching** | Composite haystack, scorer, incremental narrowing, highlight rendering | `zp` finds *Zed / pika* |
| **M4 — Polish** | Catppuccin theme, icons, config file, first-run permission flow | Shippable |
| **M5 — Tabs** | Chrome AppleScript source (background) | Tabs without latency cost |
| **M6 — Later** | Chrome extension, learned selections, other browsers | |

M1 first, before any data work: if the empty panel can't show in 16ms, nothing else matters.

---

## 15. Decisions taken

| # | Question | Decision |
|---|---|---|
| 1 | Current window in the list? | **Omitted entirely** from the empty-query list. |
| 2 | Chrome tabs in v1? | **Yes, as first-class rows**, background-refreshed, with T0→T1→T2 progressive fill so a cold start shows windows-only rather than waiting. |
| 3 | Learned query→selection memory? | **In for v1**, with decay, `ranking.learning = true`. |
| 4 | Default font / cursor | **JetBrains Mono, bundled**; static block cursor, no blink. |

## 16. Still open

1. **Distribution** — local `swift build` only, or signed + notarized? This matters more than it sounds: the Accessibility grant is keyed to the code signature, so an unsigned app re-prompts on every rebuild. Recommend an ad-hoc-stable or Developer ID signature from M1 onward purely to keep development sane.
2. **Multi-monitor** — panel on the screen with the mouse (my assumption) or the screen with the focused window?
3. ~~**Spaces** — raising a window on another Space switches Spaces (my assumption, matches macOS default), or should it pull the window to the current Space?~~ **Resolved:** raise switches Spaces, and that is the behaviour we keep. It needs `kAXMainAttribute` set before the raise and a second raise after `activate()`, or apps that restore their own front window win the race. Enumerating those windows in the first place needed §5d.
4. **Ghostty tab titles** — they currently read as the running command (`kiro-cli chat --model …`) or the cwd. Worth a Ghostty-specific title rewrite (e.g. prefer the cwd basename) to make them fuzzy-match better, or leave raw?
