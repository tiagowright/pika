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

Spaces mean AND: `z pika` requires both tokens to match, in any order.

**The `Ctrl+Space` collision:** macOS binds `Ctrl+Space` to 
*Select the previous input source*. If the
panel doesn't appear, that's almost certainly why. Clear it in *System
Settings → Keyboard → Keyboard Shortcuts → Input Sources*, or pick a
different hotkey in the config file.

## Permissions

| Permission | Required? | What happens |
|---|---|---|
| **Accessibility** | Yes | Reads window titles and raises windows. Pika prompts on first launch, then polls once a second and starts itself the moment you grant it — no relaunch needed. |
| **Automation → Google Chrome** | Optional | Lets Pika list individual Chrome *tabs*. Denied, you get one row per Chrome *window* instead, permanently and without complaint. |
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
| `~/Library/Application Support/io.github.tiagowright.pika/mru.json` | Recency data, including window titles and full Chrome tab URLs |
| `~/Library/Application Support/io.github.tiagowright.pika/learned.json` | Every query you type and the target you chose |
| `~/Library/Caches/io.github.tiagowright.pika/icons/` | App icons as PNGs, named by bundle ID |

**Read these before sharing them.** Chrome URLs can include query strings,
session tokens, document IDs, or search terms. `learned.json` links each typed
query to the target you selected, and icon filenames reveal which apps you run.
These files are plain local JSON; Pika does not add its own encryption.

In the current development build, window titles may also appear in the macOS
unified log. Do not attach Pika logs to a bug report without reviewing them.

To reset learned ranking, delete `learned.json`. There is no `--forget` flag
yet. To remove all local data, use the uninstall instructions below.

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
permissions. The current development build also registers a login item, so
Pika is available immediately after a login.

## Rebuilding Pika

If Pika stops raising windows after a rebuild, its Accessibility permission may
have changed with its code signature. See [code-signing guidance](CODE_SIGNING.md)
for the cause and a stable local-development setup.

## Configuration

`~/.config/pika/config.toml`, created with defaults on first launch. Read at
startup only — restart Pika after editing.

```toml
hotkey = "ctrl+space"        # "cmd+shift+k", "alt+space", …

[appearance]
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

The current file also contains `theme` and `font` keys. **Those are not
read yet** — the theme is fixed to Catppuccin Mocha and the font to the
bundled JetBrains Mono. They're written as placeholders; editing them does
nothing today.

## Uninstall

```sh
pkill -f '/Applications/Pika.app/Contents/MacOS/Pika'
rm -rf /Applications/Pika.app
rm -rf ~/Library/Application\ Support/io.github.tiagowright.pika
rm -rf ~/Library/Caches/io.github.tiagowright.pika
rm -rf ~/.config/pika
tccutil reset Accessibility io.github.tiagowright.pika
tccutil reset AppleEvents io.github.tiagowright.pika
```

Then remove the leftover entry under **System Settings → General → Login
Items**, and check **Privacy & Security → Accessibility**.

## Known rough edges

Named here rather than discovered by you. `requirements/SHIPPING.md` has the
full list with reasoning.

- **No UI outside the panel** — no menu bar item, no preferences window.
  Quitting means Activity Monitor or `pkill`.
- **It registers itself as a login item on first launch**, silently, without
  asking.
- **`theme` and `font` config keys are ignored**, as described above.
- **A failed hotkey registration isn't reported.** If `Ctrl+Space` is taken,
  Pika starts and simply never opens.
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
  
**Catppuccin** (MIT) for the color palette in `Theme.swift`.
