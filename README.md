# Anaclast

One Mac app for the keyboard layer, window tiling, launcher, clipboard history and machine setup.

- Replaces [sunghyun.nix](https://github.com/anaclumos/sunghyun.nix), Karabiner-Elements and Hammerspoon (owner 2026-09-23). Linux hosts are dropped.
- macOS 27 only, built against the Xcode beta SDK.
- `~/.config/anaclast/config.json` holds the keymap, tiles and shortcuts and reloads on save. `Anaclast apply` links it to [`config/dotfiles/anaclast/config.json`](config/dotfiles/anaclast/config.json).
- [`config/machine.json`](config/machine.json) holds packages, preferences, dotfiles and hosts.

## Setup

Fresh Mac, after installing Xcode from [Apple Beta](https://developer.apple.com/download/):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
/opt/homebrew/bin/brew install xcodegen
git clone https://github.com/anaclumos/anaclast.git ~/Developer/anaclast
make -C ~/Developer/anaclast build
~/Developer/anaclast/build/Build/Products/Release/Anaclast.app/Contents/MacOS/Anaclast apply
make -C ~/Developer/anaclast install
```

- `apply` runs before `install` because it links `~/.config/anaclast/config.json`, which the app needs at launch.
- First launch asks for Accessibility, which the event tap, tiling and menu actions need.
- Anaclast registers itself as a login agent that relaunches after a crash. When macOS wants approval, it opens Login Items in System Settings.
- The Accessibility grant is tied to the code signature. Sign into Xcode with the Apple ID and create an Apple Development certificate, so builds keep the grant across rebuilds.
- `security find-identity -v -p codesigning` must list that certificate. If it shows none, add Apple's [WWDR G3 intermediate](https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer) to the login keychain.
- Builds sign automatically with `-allowProvisioningUpdates`, which keeps the WeatherKit capability and the development profile current on the team.
- A Mac new to the team fails its first build with an unregistered device error. Run the Makefile's `xcodebuild` line once with `-allowProvisioningDeviceRegistration` added.
- After setup, the zsh `build` function pulls the dev repos, pushes usage, runs `make install`, then `Anaclast apply`.

## Keyboard

An event tap reads every key. Caps Lock reaches it as F18 through the HID `UserKeyMapping` property.

- Caps tap under 200 ms maximizes the window. Caps held is Hyper.
- Hyper keys tile windows, open apps and run commands. ⌘Space and Hyper Space open the launcher (owner 2026-09-23, replacing Spotlight on ⌘Space).
- A `window` action focuses an app's window whose title is `title` or is not `exceptTitle`, and otherwise runs `launch` from inside the app bundle. The launcher lists each one by its `name`. Hyper ; and Hyper ' use it for Cursor's Agents and IDE windows.
- A left ⌘ tap under 500 ms selects ABC and a right ⌘ tap selects 2-Set Korean. Any key, click or other modifier during the hold cancels the tap.
- ⌘L locks the screen and ⌘⇧V opens clipboard history. In Mail, ⌘E archives and ⌘R gets all new mail.
- Bare F4 is F4 and fn F4 is Spotlight. F5 keeps Apple's Dictation (owner 2026-09-23). Only the physical fn key counts, so an external keyboard's F4 stays F4.
- Spotlight's ⌘Space (symbolic hotkey 64) and Ask Siri (263) stay disabled, so ⌘Space belongs to the launcher and ⌘⇧Space to 1Password. Anaclast re-disables both at launch, every 60 s and on wake.
- Caps Lock is mapped only after the tap starts, and quitting clears the mapping. After a crash the mapping stays until the login agent relaunches the app, so Caps Lock sends a bare F18 in that gap while every other key works.

## Launcher

- An empty query shows tiles for the clock, weather, battery, Mail, now playing, calendar, network, CPU and memory. The first keystroke switches to app results.
- The first open asks for Calendar access, then Location, which the weather and the Wi-Fi name need.
- Mail's unread count is read only while Mail runs. The first read asks for Automation access to Mail.
- Now playing runs the `media-control` brew, a Perl bridge to MediaRemote, as one long-lived stream.
- While media plays, the notch shows the artwork on its left and a soundwave on its right. The island hides while a panel is open, on pause, and on screens without a notch.

## Settings

"Anaclast Settings" in the launcher opens General, Hyper Keys and Tiles panes. Siri, Shortcuts and the command line change the same file.

- Every change is validated, written to `config.json` and reloaded. An invalid change leaves the file untouched and shows the error.
- A key Anaclast does not know is an error at load, so no write can drop it.
- Siri and Shortcuts get seven actions. They open settings, run anything the launcher runs, set a tap timeout or tap action, bind or unbind a Hyper key and set the clipboard limit.
- Siri phrases include "Open Anaclast settings", "Anaclast Lock Screen", "Bind Hyper G in Anaclast" and "Set the Anaclast clipboard limit".
- Settings panes answer the system open intent and the launcher answers the system in-app search intent.
- Other agents use `Anaclast settings`. `get [path]` prints the config or one dotted path such as `hyper.keys.g`. `set <path> <json>` writes a value and `unset <path>` removes one.
- The command line exits 1 when a change is rejected and 2 on bad usage. The running app reloads every write.
- Without `clipboard.limit`, clipboard history keeps every item. "Keep all history" in General or `Anaclast settings unset clipboard.limit` turns that on.

## Machine

`Anaclast plan` prints what `machine.json` would change. `Anaclast apply` makes the change.

| Area | Behavior |
|---|---|
| Homebrew | Taps, brews, casks and App Store apps through one generated Brewfile. Cleanup uninstalls anything undeclared, App Store apps included, except `keep` |
| Downloads | Vendor release archives, one install entry per file. `--update` fetches them again |
| Preferences | Written through CFPreferences and read back, then the listed apps restart |
| Links, clones | Dotfiles link into `config/dotfiles`. Clones only fast-forward |
| Hosts | Names, `host.zsh` env, extra casks and `authorized_keys` follow `scutil --get LocalHostName` |
| Administrator | `sudo_local`, Remote Login, host names and App Store removals run as one `sudo` call. It asks for Touch ID first, then for the password in the terminal, or in a dialog when the window runs apply. Writing `sudo_local` needs Full Disk Access for the terminal or app that runs apply, and happens only when every PAM module it names exists |

- Destructive steps are marked in the plan and wait for a y/N answer, `--yes` or the window's confirmation. Anything replaced goes to the Trash.

## Layout

| Path | Role |
|---|---|
| `App/` | AppKit and SwiftUI glue for the event tap, panels, settings, App Intents, Accessibility, private API calls and machine apply |
| `Core/` | SwiftPM package with the keyboard engine, config schema, tiling math, search and machine planner, plus tests |
| `config/` | `machine.json` and the linked dotfiles, including Anaclast's own config |
| `Support/` | LaunchAgent plist bundled into the app |
| `project.yml` | XcodeGen spec for `Anaclast.xcodeproj` |
