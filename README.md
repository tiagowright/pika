# Pika

Pika is a blazing-fast, keyboard-first window finder for macOS.

TK: screenshots

Pika brings the fast, fuzzy **Command-P** file-switching pattern from editors
such as Zed and VS Code to the windows you already have open. Press a hotkey,
type a couple of letters from an app or window title, then press `Enter` to
jump to that exact window. Pika lists open windows across Spaces and, when
enabled, individual Chrome tabs. Ghostty's native tabs appear as windows.

**Local by design.** Pika reads window titles through macOS Accessibility so
it can find and raise the window you choose. It sends nothing over the network;
the local data it stores—including the sensitive parts—is described in
[Privacy and local data](#privacy-and-local-data).

It is keyboard driven:
`Ctrl+Space` brings up the switcher, which allows you to search for
the window using a few letters and fuzzy matching, then `Enter` to switch. 
For example, after `Ctrl+Space`:
- `zp` finds the window `Zed · pika — README.md`, because both
characters landed on word beginnings.
- `fp` finds the window `Finder · pika`
- `ghpi` finds the tab `Ghostty · pika/`
- `gcpi` finds the tab `Google Chrome · pika/README.md at main`
- `Enter` brings you back to the last window you were.

## Blazing fast

Pika was architected to make window switching feel as immediate as editor file
switching. Open apps, windows, and Chrome tabs are indexed off the UI path and
updated in the background. When the switcher opens, it searches an in-memory
snapshot—never waiting for Accessibility or Chrome—so each keystroke can update
the matches immediately.

| Interaction | Average response |
|---|---:|
| Hotkey → visible switcher | `TK ms` |
| Keystroke → updated results | `TK ms` |
| `Enter` → switcher dismissed | `TK ms` |

## Keys

| Key | Action |
|---|---|
| `Ctrl+Space` | Toggle — opens if hidden, closes if already open |
| `Esc` | Dismiss, clear the query |
| `Enter` | Activate the selected row |
| `↓` / `Ctrl+N` | Next row (stops at the end, no wrap) |
| `↑` / `Ctrl+P` | Previous row (stops at the top) |
| `Ctrl+W` | Delete the previous word |
| `Ctrl+U` | Clear the query |
| `Backspace` | Delete a character |
| `⌘,` | Open Settings (so does clicking the pika in the switcher) |

Spaces mean AND: `z pika` requires both tokens to match, in any order.

**The `Ctrl+Space` collision:** macOS binds `Ctrl+Space` to 
*Select the previous input source*. If the
panel doesn't appear, that's almost certainly why. Pika detects the clash
and puts an orange dot on its menu bar icon; the menu links to *System
Settings → Keyboard → Keyboard Shortcuts → Input Sources*, where you can
clear it. Or record a different hotkey in Settings → General.

## Menu bar and Settings

Pika's menu bar icon (a leaping pika) is how you quit, switch the theme, and
open Settings. An orange dot on it means something needs you — a
missing permission, a hotkey that won't fire, or a config line Pika
couldn't use — and the menu says what and links to the fix.

Settings (`⌘,` from the menu or from the switcher) has every option in
`config.toml`, a hotkey recorder, and a Permissions page showing what's
granted and how to fix what isn't. If the notch hides the menu bar icon,
open Pika.app again from Spotlight or Finder: while Pika is running, that
opens Settings. While Settings or first-run setup is open, Pika shows in
the Dock and in ⌘Tab like any app, so you can go to System Settings and
come back; it disappears from both again when you close the window.

## Permissions

| Permission | Required? | What happens |
|---|---|---|
| **Accessibility** | Yes | Reads window titles and raises windows. First-run setup explains it before macOS asks, and Pika starts itself the moment you grant it — no relaunch needed. |
| **Automation → Google Chrome** | Optional | Lets Pika list individual Chrome *tabs*. Skip it in setup, or deny it, and you get one row per Chrome *window* instead. |
| **Screen Recording** | Never asked | Titles come from the Accessibility API precisely so this second scary prompt isn't needed. |

## Privacy and local data

Pika makes **no network connections** and has no telemetry, analytics, or crash
reporting. The window index used while you search is held in memory; Pika does
persist a small amount of local state so it can remember recency and learned
ranking.

Accessibility lets Pika read the title of every open window and raise the one
you select. If you grant **Automation → Google Chrome**, Pika also reads Chrome
tab titles and URLs to list individual tabs. Screen Recording and Input
Monitoring are deliberately not requested.

| Path | Contents |
|---|---|
| `~/.config/pika/config.toml` | Your settings |
| `~/Library/Application Support/io.github.tiagowright.pika/mru.json` | Recency data, including window titles and full Chrome tab URLs. Entries older than 30 days are dropped |
| `~/Library/Application Support/io.github.tiagowright.pika/learned.json` | Queries you typed and the target you chose. Fades by 2% a day; at most 500 queries |
| `~/Library/Application Support/io.github.tiagowright.pika/state.json` | Setup progress, skipped setup items, and the last Chrome permission answer |
| `~/Library/Caches/io.github.tiagowright.pika/icons/` | App icons as PNGs, named by bundle ID |

**Read these before sharing them.** Chrome URLs can include query strings,
session tokens, document IDs, or search terms. `learned.json` links each typed
query to the target you selected, and icon filenames reveal which apps you run.
These files are plain local JSON; Pika does not add its own encryption.

In the current development build, window titles may also appear in the macOS
unified log. Do not attach Pika logs to a bug report without reviewing them.

**Settings → Privacy & Data** lists each file with a *Show in Finder*
button, and can clear recency, forget learned queries, or delete the icon
cache. To remove all local data, use the uninstall instructions below.

## Build and install

No downloadable installers available yet. The app is currently for those
ready to install from github. Tested on macOS 26, Apple Silicon, with 
Swift 6.4 (command line tools is enough).

```sh
git clone https://github.com/tiagowright/pika.git
cd pika
./install.sh
```

`install.sh` builds, tells you what it's about to do, and asks before it
quits a running Pika and replaces `/Applications/Pika.app`. 
Installing to `/Applications` gives Pika a stable app location for Accessibility
permissions.

On first launch, a short setup walks through what Pika needs:
Accessibility (required), Chrome tabs and starting at login (both
optional, each with a Skip), and a check that your hotkey works. It ends
by having you press the hotkey once. Run it again any time from
Settings → Permissions → *Run Setup Again*.

## Rebuilding Pika

If Pika stops raising windows after a rebuild, its Accessibility permission may
have changed with its code signature. See [code-signing guidance](CODE_SIGNING.md)
for the cause and a stable local-development setup.

## Running the tests

```sh
swift test
```

With only the Command Line Tools installed, `swift test` sometimes fails
with *plugin for module 'TestingMacros' not found* on every test. A rerun
usually passes; that error can also hide an ordinary compile error in a
test file. If Xcode is installed, running the same command with its
toolchain is reliable and shows the real error:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Screenshot tests of the switcher, the menu bar icon, Settings, and setup
are opt-in: set `PIKA_SNAPSHOT_DIR` to a folder, and they write PNGs there.
The Settings and setup ones briefly put windows on screen.

## Configuration

`~/.config/pika/config.toml`, created with defaults on first launch.
Settings reads and writes this file (keeping your comments), and Pika
watches it, so edits made either way apply as soon as they're saved.
Unknown keys or invalid values are logged and ignored, and the rest of
the file still applies.

```toml
hotkey = "ctrl+space"        # "cmd+shift+k", "alt+space", …

[appearance]
theme        = "auto"        # auto (follow macOS), dark, or light
font_size    = 13
width        = 680
max_rows     = 10
show_icons   = true

[appearance.cursor]
blink = false

[ranking]
recency_weight  = 40         # how much recency nudges a match
learning        = true       # remember which target you pick per query
learn_weight    = 60
include_current = false      # list the window you're already in

[sources]
chrome_tabs = true
```

`dark` is Catppuccin Mocha and `light` is Catppuccin Latte. `auto` follows
macOS and switches live when the system does. The font is always the
bundled JetBrains Mono; an older config's `font` key is reported as
ignored and can be deleted.

## Uninstall

```sh
./uninstall.sh              # add --keep-data to keep your config and history
```

Then remove the leftover entry under **System Settings → General → Login
Items**, and check **Privacy & Security → Accessibility**.

## Known rough edges

Named here rather than discovered by you. `requirements/SHIPPING.md` has the
full list with reasoning.

- **Resetting a stuck Accessibility grant needs Terminal.** If the switch
  in System Settings won't stay on, Settings → Permissions shows the
  `tccutil reset` command to copy; Pika can't yet run it for you.
- **No downloadable build yet**, so no notarization: install from source.
- **Window titles for other Spaces can be stale.** Accessibility titles are
  Space-scoped, so a window you haven't visited since renaming shows its old
  title until you do.

## Licence

MIT — see [LICENSE](LICENSE).

Bundled third-party work, with full notices in
[THIRD-PARTY.md](THIRD-PARTY.md):

**JetBrains Mono** under the SIL Open Font License 1.1. The licence text sits beside the font at
  [`Sources/Pika/Resources/JetBrainsMono-OFL.txt`](Sources/Pika/Resources/JetBrainsMono-OFL.txt)
  and is copied into the `.app` bundle, as the OFL requires.
  
**Catppuccin** (MIT) for the Mocha and Latte palettes in `Theme.swift`.
