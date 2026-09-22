# Pika

Pika is a very fast macOS window and app switcher. It is inspired by modern
editors fast and fuzzy file switching experiences. The app is architected
to respond instantly even with tons open apps, search at the speed of typing, and
switch immediately. Pika lists every open window across every Space, and even individual tabs
inside many apps (including Chrome tabs and Ghostty). Type a
couple of characters, press Enter, and that window is in front of you. It is keyboard driven:
`Ctrl+Space` brings up the switcher, which allows you to search for
the window using a few letters and fuzzy matching, then `Enter` to switch.

Examples:
- `Ctrl+Space` then `zp` finds `Zed · pika — ARCHITECTURE.md`, because both 
characters landed on word beginnings. `Enter` then switches to that window.
- `Ctrl+Space` then `gcdr` finds `Google Chrome · Home - Google Drive`
- `Ctrl+Space` then `Enter` brings you back to the last window you were.

## Screenshots

To be added. `TK`

## Blazing fast

Pika was architected to reduce switching latency as much as possible.
To achieve this, open apps, windows, and tabs are indexed in a separate
process independent of the user interface. Indexing is event driven, to
reduce resources. When the user calls up the switcher with `Ctrl+Space`,
the index is read from the file and fuzzy search happens quickly in memory,
fast enough that every key press responds immediately with updated
matches. Every interaction is designed to respond in milliseconds.

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

### The `Ctrl+Space` collision

macOS binds `Ctrl+Space` to **Select the previous input source**. If the
panel doesn't appear, that's almost certainly why. Clear it in **System
Settings → Keyboard → Keyboard Shortcuts → Input Sources**, or pick a
different hotkey in the config file.

## Privacy

Pika runs locally on your machine and never communicates over the network.
The app does save the live index of open windows on a file in your drive,
so that the app can respond instantly to every request. This file is placed
`TK`, and it is secured by the standard encryption that your MacOS
provides for all your personal data.

## Permissions

| Permission | Required? | What happens |
|---|---|---|
| **Accessibility** | Yes | Reads window titles and raises windows. Pika prompts on first launch, then polls once a second and starts itself the moment you grant it — no relaunch needed. |
| **Automation → Google Chrome** | Optional | Lets Pika list individual Chrome *tabs*. Denied, you get one row per Chrome *window* instead, permanently and without complaint. |
| **Screen Recording** | Never asked | Titles come from the Accessibility API precisely so this second scary prompt isn't needed. |

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
Installing to `/Applications` is deliberate to enable launch at login
and providing the necessary Accessibility permissions.

## Code signing — read this if Pika stops working after a rebuild

macOS keys the Accessibility permission to the app's **code signature**. An
ad-hoc signature is different on every build, so an ad-hoc Pika loses its
permission every time you rebuild and then silently stops raising windows,
with no error anywhere.

`build.sh` picks a signing identity, first match wins:

1. `$PIKA_SIGN_IDENTITY`
2. `.signing-identity` — a one-line file in the project root, gitignored
3. A `Developer ID Application` certificate in your keychain
4. Ad-hoc, with a warning explaining the above

For comfortable local development, make a stable identity once:

**Keychain Access → Certificate Assistant → Create a Certificate…** → any
name, Identity Type **Self Signed Root**, Certificate Type **Code Signing**.
Then:

```sh
echo "My Local Signing" > .signing-identity
```

The first build with a new key raises a keychain prompt. Choose **"Always
Allow"** — with plain "Allow" every subsequent build blocks on the same
dialog.

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

## What Pika stores, and where

Pika makes **no network connections** and has no telemetry, analytics, or
crash reporting of any kind. Everything below stays on your machine.

| Path | Contents |
|---|---|
| `~/.config/pika/config.toml` | Your settings |
| `~/Library/Application Support/io.github.tiagowright.pika/mru.json` | Recency per target |
| `~/Library/Application Support/io.github.tiagowright.pika/learned.json` | Which target you pick for a given query |
| `~/Library/Caches/io.github.tiagowright.pika/icons/` | App icons as PNGs, named by bundle ID |

**Worth knowing before you share any of these.** A tab's stable identity
*is* its URL, so `mru.json` contains **full Chrome tab URLs including query
strings**, alongside window titles. `learned.json` contains every query
you've typed and what it resolved to. The icon filenames alone list the apps
you run. It's all plain JSON owned by your user, so read these before
attaching them to a bug report.

To reset learned ranking, delete `learned.json`. There's no `--forget` flag
yet.

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

- **JetBrains Mono** under the SIL Open Font License 1.1. The licence text
  sits beside the font at
  [`Sources/Pika/Resources/JetBrainsMono-OFL.txt`](Sources/Pika/Resources/JetBrainsMono-OFL.txt)
  and is copied into the `.app` bundle, as the OFL requires.
- **Catppuccin** (MIT) for the Mocha palette in `Theme.swift`.
