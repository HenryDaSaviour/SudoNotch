# SudoNotch

A notch for your Mac. It works on MacBooks with or without a real notch (macOS 14 or newer).
Hover the top of the screen to open it.

- **Music**: now playing and controls for Music and Spotify
- **Clipboard**: the last 30 things you copied
- **Shelf and AirDrop**: drop files on the notch, send them with AirDrop
- **Tools**:
  - Keyboard lock for cleaning your keyboard
  - Awake with the lid closed, with a timer (15 min to 12 hours, or until a clock time)
  - Caffeinate without opening Terminal
- Battery, Bluetooth, volume and brightness popups in the notch
- Rounded screen corners and hot-corner animations on Macs without a notch

## Install

Download `SudoNotch.dmg` from [Releases](../../releases/latest), open it, and drag SudoNotch to Applications.
The latest release is signed and notarized by Apple.

The first time you turn on "Awake with lid closed", macOS asks for your password once. SudoNotch then installs a narrow
rule (`/etc/sudoers.d/sudonotch`) that allows only `pmset -a disablesleep 0|1` without a password. You can remove it in
Settings. Don't put a Mac in a bag while that mode is on.

## Build

```bash
./scripts/build.sh --install     # build and install to /Applications
./scripts/build.sh --dmg         # universal build, writes dist/SudoNotch.dmg
SIGN_ID="Developer ID Application: ..." ./scripts/notarize.sh <keychain-profile>   # sign + notarize (needs your own Apple developer account)
```

Without `SIGN_ID` the app is ad-hoc signed, and macOS will ask you to use "Open Anyway" the first time.

## Releases

- **v1.0.0**: SudoNotch, notarized, Spotlight-style controls, lid-closed timer, Caffeinate, smoother open and close animation.
- **v0.1.0-pseudonotch**: the first build, when the app was still called PseudoNotch. Ad-hoc signed, so it needs "Open Anyway". Kept for history.
