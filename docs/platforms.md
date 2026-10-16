# Platform behaviour and permissions

What each OS allows a clipboard manager to do, which permissions Clipboard
Sync needs, and what the app does about the gaps. Settings → *Permissions*
shows the same guidance in-app together with a live **Test** button.

| | Background capture | Global hotkey | Start at login | OS permission prompts |
|---|---|---|---|---|
| macOS | Yes: polls `NSPasteboard.changeCount`, reads on change | Yes (Carbon `RegisterEventHotKey`, no Accessibility access needed) | Launch Agent in `~/Library/LaunchAgents` | Possible one-time pasteboard prompt on macOS 26+; Local Network prompt for LAN databases; keychain prompt on unsigned builds (see below) |
| Windows | Yes, `AddClipboardFormatListener` | Yes (`RegisterHotKey`) | `HKCU\…\Run` value | None |
| Linux (X11 / XWayland) | Yes, GTK clipboard polling | Yes (keybinder) | `~/.config/autostart/*.desktop` | None. Secret Service (GNOME Keyring / KWallet) used for credentials when present |
| Linux (native Wayland) | Only while focused | No | same | The app defaults to XWayland (`GDK_BACKEND=x11`); set `GDK_BACKEND=wayland` to override |
| Android | No, Android 10+ serves clipboard reads only to the focused app | n/a | n/a | No permission exists. Android 12+ shows a "pasted from …" notice on each read |
| iOS | No: never in background | n/a | n/a | "Allow Paste?" on reads of content from other apps unless *Settings → Nija → Paste from Other Apps → Allow*; Local Network prompt for LAN databases |

## Sensitive-content hints

Password managers mark clipboard content as "do not record". With *Skip
password-manager content* on (default) the app checks the hint **before**
reading the clipboard:

| Platform | Hint honoured |
|---|---|
| macOS | `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType` |
| Windows | `ExcludeClipboardContentFromMonitorProcessing` clipboard format |
| Android 13+ | `ClipDescription.EXTRA_IS_SENSITIVE` |
| iOS, Linux | no standard hint exists, use *Skip keys and tokens* or *Pause capture* |

Pairing: scanning a QR code needs the camera (Android, iOS). Desktops paste
the copied code instead.

## Universal Clipboard

On macOS and iOS, Apple's Universal Clipboard copies what you copy on one
Apple device onto the others signed in to the same Apple Account. If Nija
recorded that copy too, the clip would carry the receiving device's name,
and the original synced by the device that made it would then be dropped as
an echo, so every device would show the clip as its own.

While syncing, Nija therefore skips clipboard content marked
`com.apple.is-remote-clipboard` and leaves it to Nija on the device it came
from. *Settings → Capture → Leave Universal Clipboard to its device* turns
this off, for when that device does not run Nija. In local-only mode the
copy is always recorded, since nothing else would bring it in.

## Mobile capture flow

Copy in any app → open Nija (or tap **Capture**) → the app reads
the clipboard on resume. Android hands window focus over slightly after the
`resumed` lifecycle event, so the read is delayed 400 ms and retried once.
On iOS the app checks `hasStrings` first, which does not trigger the paste
prompt, and only reads when there is something to read.

## macOS keychain and unsigned builds

Credentials are stored in the login keychain. macOS binds each keychain item
to the signature of the app that created it. Release builds are currently
**unsigned** (ad-hoc signature), so after updating the app macOS shows
"Nija wants to use your confidential information stored in …",
click **Always Allow**. The app never blocks on that prompt: startup reads
only preferences, secrets are loaded after the first frame, and every
keychain call is bounded by a 10 s timeout with a preferences fallback that
is surfaced as a warning in Settings. Code-signing the release (see
`docs/release.md`) removes the prompt entirely.

## Data protection

- Android: `allowBackup="false"` and data-extraction rules exclude all app
  data from cloud backup and device transfer.
- macOS: the app runs without the App Sandbox (it is not distributed through
  the App Store) so it can register the Launch Agent and read the pasteboard
  from the menu bar.
- All platforms: credentials go to the OS credential store; the local history
  database stays in the app's private data directory.
