# Pika — UX Outline

> A terminal-styled window switcher for macOS.
> **The whole product is one sentence:** `Ctrl+Space`, two or three letters, `Enter`.

---

## 1. Design principles

1. **The 250ms rule.** Any perceptible pause is a bug. Panel must be on screen in well under 50ms; every keystroke must repaint within one frame. If data isn't ready, we show what we have and fill in silently — we never make the user wait for a source.
2. **Hotkey + Enter is sacred.** With an empty query, the top row is *always* the window you were in before this one. That one gesture is a full alt-tab replacement and must never be wrong or ambiguous.
3. **Terminal, not Spotlight.** Monospace, dense rows, high contrast, hard edges, no drop shadow theatre, no easing curves that delay input. It should look like it belongs next to Ghostty.
4. **Never block on a source.** Chrome, Slack, and the Accessibility API can all hang for seconds. The UI is driven by a cache that is always instantly readable; sources push into it from the background.
5. **Keyboard only.** The mouse works (click a row) but nothing requires it, and no feature is mouse-only.
6. **Only what's open.** No app launching, no recent files, no closed windows. Reduced scope is what makes it fast and predictable.

---

## 2. Anatomy

```
        ┌──────────────────────────────────────────────────────────────┐
        │  ❯ zp█                                                       │
        ├──────────────────────────────────────────────────────────────┤
        │▌ ▣  Zed        pika — ARCHITECTURE.md                    12s │
        │  ▣  Zed        zprofile — dotfiles                        4m │
        │  ▣  Ghostty    ~/Projects/Python/leet/appswitch/pika       1m │
        │  ▣  Chrome     Pika App Icon Design — Gemini              8m │
        │  ▣  Chrome     Zora — Learnings from Bottom Input…       22m │
        │  ▣  Slack      #proj-pika (Acme)                           1h │
        └──────────────────────────────────────────────────────────────┘
         │  │   │          │                                         │
         │  │   │          │                                         └─ recency, dim
         │  │   │          └─ window / tab title, matched chars accented
         │  │   └─ app name, matched chars accented
         │  └─ 16pt app icon
         └─ selection bar (accent)
```

| Element | Spec |
|---|---|
| Panel width | Fixed `680pt`. Fixed width means no re-layout as content changes. |
| Panel position | Horizontally centred, vertical centre biased upward (~38% from top) on the screen containing the mouse. |
| Rows visible | Max **10**. Never render more; the list scrolls the selection, it does not grow the panel. |
| Row height | Constant, derived from the monospace line height (~26pt). Constant height = O(1) scroll math, no measurement pass. |
| Font | **JetBrains Mono, bundled with the app** so it renders identically regardless of what's installed. One family for everything. Input at 15pt, rows at 13pt. |
| Prompt glyph | `❯` in accent colour, then the query, then a solid block cursor `█`. **No blink** — a blinking cursor is a redraw every 500ms on an otherwise idle app, and buys nothing here. |
| Corner radius | 6pt. Thin 1pt border in `surface1`. No shadow, or a very tight one. |
| Column alignment | App-name column is fixed width (~14ch, truncated with `…`); titles start at the same x on every row. This is what makes it read as a terminal rather than a list. |

---

## 3. States

| # | State | What's shown |
|---|---|---|
| **S0** | Hidden | Nothing. Process resident, index live. |
| **S1** | Open, empty query | MRU order. **Row 0 = the window you were in before this one**, pre-selected. Rows 1..n = progressively older. |
| **S2** | Open, query, matches | Fuzzy-ranked. Selection resets to row 0 on every query change. |
| **S3** | Open, query, no matches | Rows replaced with a single dim line: `no matching window`. Enter does nothing (no beep, no flash). |
| **S4** | Activating | Panel hides *immediately* on Enter, before the target is raised. Perceived latency = 0. If the raise fails, we do nothing visible. |

**S1 → S2 transition is the important one.** The very first character typed switches the ordering model from "recency" to "match quality + recency". Selection snaps back to row 0.

---

## 4. Keymap

| Key | Action |
|---|---|
| `Ctrl+Space` | Toggle. Opens if hidden; **closes if already open** (so a double-tap is a no-op escape hatch). |
| `Esc` | Dismiss, no action. Query is cleared. |
| `Enter` | Activate the selected row. Panel hides first. |
| `↓` / `Ctrl+N` | Next row (stops at end — no wrap; wrapping causes overshoot mistakes). |
| `↑` / `Ctrl+P` | Previous row (stops at top). |
| `Ctrl+W` | Delete previous word in the query. |
| `Ctrl+U` | Clear the query (returns to S1 / MRU). |
| `Backspace` | Delete char. Deleting the last char returns to S1 MRU ordering. |
| `Tab` | *(proposed)* Accept the selected row's app name into the query as a filter, so you can then narrow within that app. |
| Click a row | Activate it. |
| Click outside / lose key | Dismiss. |

Chording note: `Ctrl+Space` is bound by macOS to **Select the previous input source**. First-run setup has to detect this and tell the user to clear it in *System Settings → Keyboard → Keyboard Shortcuts → Input Sources*, or offer an alternate default.

---

## 5. What gets listed (a "target")

A row is one **activatable target**. Three kinds:

| Kind | Example row | Enter does |
|---|---|---|
| **Window** | `Zed · pika — ARCHITECTURE.md` | Raise that window, activate its app. |
| **Tab** (Chrome) | `Chrome · Usernames — Google Sheets` | Raise the window, then select that tab. |
| **App with no windows** | `Messages` | Activate the app (it will show its window). |

Ghostty is a special (happy) case: it uses native macOS window tabbing, so **each Ghostty tab already is a window** and needs no special handling.

Slack has no scripting support, so a Slack row is the window title only — which conveniently already reads as `#channel (Workspace)`.

### Chrome tabs fill in; they never make you wait

Reading Chrome's tabs costs ~70ms, which is too slow for a keystroke but cheap enough to refresh constantly in the background. So Chrome rows have two levels of detail, and the panel always shows whatever is ready:

| | What you see | When |
|---|---|---|
| **Cold** (first seconds after login, or Chrome just restarted) | One row per Chrome **window**, titled by its active tab | Immediately |
| **Warm** (steady state, ~always) | One row per **tab** | Within a few hundred ms of launch, then continuously |

The focused Chrome window's tabs are loaded first, then the rest in recency order — so the tabs you're most likely to want are the first to become searchable.

Two rules make this invisible rather than annoying:

1. **Rows only ever get more specific, never less.** A Chrome window row is replaced by its tab rows; nothing disappears.
2. **Fill-in never moves your selection.** If tabs land while the panel is open, the row you had selected stays selected (selection tracks identity, not index).

If Automation permission for Chrome is denied, Pika stays permanently in the Cold presentation. That's a graceful degradation, not an error state — no warning, no nag.

---

## 6. Ranking, as the user perceives it

**Empty query:** pure MRU. Previous window first.

**With a query:** the list is ordered by `match quality` first, with recency used as a *tiebreaker and a nudge* — never enough to float a poor match above a good one.

The matcher treats a target as one composite string:

```
    "Zed  pika — ARCHITECTURE.md"
     ^     ^
     z     p
```

so typing `zp` scores extremely well because both characters landed on **word beginnings**, one in the app name and one in the title. That's the core interaction the whole thing is designed around.

Scoring intuition (details in `TECHNICAL.md`):

- Huge bonus: character matches the **first letter of the app name**.
- Large bonus: character matches a **word start** in the title (after a space, `-`, `_`, `/`, `.`, `—`, or a camelCase boundary).
- Bonus: **consecutive** matched characters.
- Penalty: gaps, and characters matched deep inside a word.
- Nudge: recency, bounded so it can only reorder comparably-good matches.
- Nudge: **learned selections** — if you've typed `sl` and chosen Slack five times, `sl` starts pinning Slack to the top.

**Spaces mean AND.** `z pika` = both tokens must match, in any order. Useful when the greedy subsequence guesses wrong.

Matched characters are drawn in the accent colour in both columns, so the ranking is self-explaining — you can see *why* a row won.

### It learns

Pika remembers which target you chose for a given query. Type `sl`, pick Slack a few times, and `sl` will put Slack first even when a Chrome tab technically scores higher on text alone.

Three constraints keep this from becoming spooky:

- **Bounded.** A learned preference nudges; it can't float a target that doesn't match the query at all, and it can't beat a dramatically better fresh match.
- **It forgets.** Counts decay slowly, so a project you stopped working on stops hijacking its letters after a few weeks. No manual cleanup.
- **It's resettable.** `pika --forget` clears the model; `ranking.learning = false` disables it.

It applies to query *prefixes* too, so learning `slack` also improves `s`, `sl`, and `sla`.

---

## 7. Theme

Catppuccin Mocha as the shipped default. Every colour is a named token so a config file can swap the whole palette (Latte/Frappé/Macchiato, or anything else) without touching code.

| Token | Mocha | Used for |
|---|---|---|
| `bg` | `#1e1e2e` base | Panel background |
| `bg_input` | `#181825` mantle | Query row background |
| `border` | `#45475a` surface1 | Panel border, separator |
| `fg` | `#cdd6f4` text | Window/tab title |
| `fg_dim` | `#7f849c` overlay1 | Recency column, app name of unselected rows |
| `fg_muted` | `#6c7086` overlay0 | Empty-state text, placeholder |
| `accent` | `#cba6f7` mauve | Prompt glyph, selection bar, matched characters |
| `accent_alt` | `#89b4fa` blue | App-name column |
| `sel_bg` | `#313244` surface0 | Selected row background |
| `warn` | `#f9e2af` yellow | Degraded-source indicator |

> Verify hexes against `catppuccin/catppuccin` before shipping — these are from memory.

Config sketch (`~/.config/pika/config.toml`):

```toml
hotkey = "ctrl+space"

[appearance]
theme        = "catppuccin-mocha"   # or a [colors] table below
font         = "JetBrains Mono"   # bundled
font_size    = 13
width        = 680
max_rows     = 10
show_icons   = true

[ranking]
recency_weight  = 40      # 0 disables recency entirely
learning        = true    # remember query -> selection
learn_weight    = 60
include_current = false   # current window omitted from the empty-query list

[appearance.cursor]
blink = false

[sources]
chrome_tabs  = true
slack        = "windows"  # windows | off
```

---

## 8. Motion and feedback

Deliberately almost none.

- **Appearance:** instant. No fade-in, no scale-up. A 120ms fade is 120ms of latency, and this is the one interaction where it would be felt every single time.
- **Dismissal:** instant.
- **Selection move:** instant. No animated selection bar sliding between rows.
- **Cursor:** block cursor. Blinking is optional and off by default (each blink is a redraw on an idle app).
- The only acceptable animation is a *fill-in*: if a slow source (Chrome tabs) lands while the panel is open, new rows appear without moving the current selection.

---

## 9. Edge cases

| Situation | Behaviour |
|---|---|
| Panel open, you switch Spaces / an app opens a window | List updates live, but **the selected target stays selected** (selection follows identity, not index). |
| Target window was closed between opening the panel and pressing Enter | Silently fall back to activating that app; if the app is gone, dismiss and do nothing. |
| Target window is minimised | Un-minimise, then raise. |
| Target window is on another Space | Raise it; macOS switches Spaces. (Alternative — move it to the current Space — is a per-app-flag question, not v1.) |
| Target is fullscreen | Panel is `.fullScreenAuxiliary` so it draws over fullscreen apps; activation switches to that fullscreen Space. |
| Pika's own panel | Never appears in the list, and focusing it never disturbs the MRU stack. |
| The window you're currently in | **Omitted** from the empty-query list entirely, so row 0 is unambiguously the previous window and no row is a no-op. It reappears once you type, since it can be a genuine match. |
| An app is hung (beachball) | Its windows still list from cache with a dim `warn`-coloured marker; we never wait on it. |
| Only one window is open | List shows it; hotkey+Enter re-focuses it (harmless no-op). |
| No windows at all | Empty state: `no open windows`. |
| Duplicate titles (10 Chrome tabs named "Inbox") | Disambiguate with a dim suffix — window index or profile name. |
| Very long titles | Middle-truncate with `…`, keeping the head and the tail (the tail usually holds the filename). |

---

## 10. First-run

Pika needs Accessibility permission and cannot work at all without it. First run shows a single small panel in the same visual language:

```
    ❯ pika needs Accessibility access to see and raise windows.

      ▌ Open System Settings
        Learn why
```

Chrome tab access asks for Automation permission separately, and only the first time Chrome is seen — and Pika stays fully usable if it's denied.

---

## 11. Explicitly out of scope for v1

- Launching applications that aren't running
- Recent/closed windows, files, browser history
- Window management (move, resize, tile)
- Bookmarks, calculators, unit conversion, or any other Spotlight-ish surface
- Multi-select or actions-on-a-row menus
- Non-Chrome browser tabs (Safari, Arc, Firefox) — same mechanism, later
- Slack channel enumeration beyond the window title
