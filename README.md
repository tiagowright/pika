# Pika

A macOS window switcher. **`Ctrl+Space`, two or three letters, `Enter`.**

Pika lists every open window across every Space, every Chrome tab, and every
running app that has no windows — as one flat, fuzzy-searchable list. Type a
couple of characters, press Enter, and that window is in front of you.

Typing `zp` finds `Zed · pika — ARCHITECTURE.md`, because both characters
landed on word beginnings. That's the whole interaction.

## Status

v0.1, a personal project published in case it's useful. It has only ever run
on **macOS 26.6 on Apple Silicon**, which is why it claims exactly that and
no more. Support is best-effort. There is no notarized download yet — you
build it yourself.

`requirements/` holds the design documents: `UX.md` (product), `TECHNICAL.md`
(implementation), `SHIPPING.md` (an honest list of what this still needs).

## Requirements

- **macOS 26 or later.** `LSMinimumSystemVersion` is set to `26.0` because
  that's the only floor that's been tested, rather than a lower number that
  looks more generous and might not work.
- **Apple Silicon.**
- **Swift 6.4.** Full Xcode is *not* required — Command Line Tools is enough.

## Build and install

```sh
git clone https://github.com/tiagowright/pika.git
cd pika
./install.sh
```

`install.sh` builds, tells you what it's about to do, and asks before it
quits a running Pika and replaces `/Applications/Pika.app`. Pass `--yes` to
skip the prompt in a script. `./build.sh` on its own produces `Pika.app` in
the project directory without installing anything.

> **Don't leave a built `Pika.app` in the project directory while another
> copy is installed in `/Applications`.** Two bundles claiming the same
> `CFBundleIdentifier` make the app impossible to add to Accessibility —
> macOS resolves an identifier back to a path to draw those rows, and with
> two candidates the row silently never appears. `install.sh` deletes the
> intermediate for you; if you've been using `build.sh` directly, run
> `rm -rf Pika.app` before granting permissions.

Installing to `/Applications` is deliberate, not cosmetic: `SMAppService`
ties the login-item registration to the bundle's location on disk, so a Pika
run out of a project directory loses "launch at login" the moment that
directory moves.

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

## Permissions

| Permission | Required? | What happens |
|---|---|---|
| **Accessibility** | Yes | Reads window titles and raises windows. Pika prompts on first launch, then polls once a second and starts itself the moment you grant it — no relaunch needed. |
| **Automation → Google Chrome** | Optional | Lets Pika list individual Chrome *tabs*. Denied, you get one row per Chrome *window* instead, permanently and without complaint. |
| **Screen Recording** | Never asked | Titles come from the Accessibility API precisely so this second scary prompt isn't needed. |

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

The generated file also contains `theme` and `font` keys. **Those are not
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
yet, despite what `UX.md` §6 promises.

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
