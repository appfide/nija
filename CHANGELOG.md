# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[SemVer](https://semver.org/).

## [Unreleased]

### Added
- **Sync marker on every clip.** With a database connected, each clip in the history shows a small cloud: *In Supabase* (sent from here or received from another device), *Waiting to sync*, or *Only on this device* (copied while database sync was off, the device was paused or receive-only, or before switching databases). Tap or hover it for the words; the clip preview says the same.

### Fixed
- **Signed groups on PocketBase dropped every clip.** A clip's signature covered its times to the microsecond, and PocketBase keeps them to the millisecond, so each device rejected the other devices' clips as badly signed. Clips and device rows are now signed with their times cut to the millisecond, which reads the same from every database, so existing signatures on Supabase still verify.
- **Sync no longer freezes on a request that never answers.** A Mac that started before its network was up could wait forever on its first database request: no heartbeat, nothing sent, nothing received and, because capture waited for sync to start, nothing recorded either, while the app still said *Synced*. Every database request now has a deadline (20 seconds for device rows, 2 minutes for clips) and fails like any network error, and clipboard capture starts without waiting for the database.
- A clip sealed with a key version that had not reached the device yet (sent right after *Rotate key*, before the device's next check-in) was skipped for good. The device now picks up its new key first.
- After handing out a fresh key because a device held a different one, the admin also sends its own clips again under the new key, so what it copied while the keys disagreed reaches the other devices, and devices on 0.5.0, which stop syncing at the first clip they cannot open, start again.
- Switching to another database (another type, or another project of the same type) now reads the new one from the beginning and marks the history already on this device as *Only on this device*. It used to keep the read position of the old Supabase project when moving to a new one, skipping its older clips.
- **Devices that ended up with different encryption keys now get back in step on their own.** When a device of a signed group lost its keys and started over (after leaving the group, or *Change passphrase* on one device), it sealed clips with a key the others did not have, and the others did the same to it. Each side silently dropped the other's clips, and the only hint was a key fingerprint to compare by hand, which could not fix it. The admin device now notices it, from a member that holds a newer key version than its own or from a member's clip that does not open, and hands every member a fresh random key, sealed to each device, numbered above every version in the group. Members need no update for this; the admin device does. A clip that does not open no longer stops the whole download with *wrong passphrase* in a signed group either; it is skipped. *Settings → Privacy* says when another device holds a different key.
- *Change passphrase* on the admin of a signed group changed the key on that device only. It now hands the new passphrase to every member, like *Rotate key* in *Devices*.
- A device that was once removed from a group could never join that database again: its old row, still marked *removed*, made it disconnect itself seconds after every connect and forget the credentials (and, with *Start a new group*, the admin key it had just created, which failed with *No admin key*). A device joining with typed credentials now replaces such a row with a fresh one. A row marked *blocked* still applies, and in a signed group the new row waits for the admin like any new device.
- macOS showed *OS credential store unavailable* after connecting a database that has no password, such as Supabase with an anon key, although every credential was in the keychain. Clearing a credential the keychain never held failed there (the macOS file keychain answers with -34018 because the storage plugin also clears the iCloud copy), and the app retried that delete on every launch. A credential that is not in the keychain now counts as already deleted.

### Changed
- The desktop tray moved to tray_manager 0.8, which drives the icon and menu through one native core on macOS, Windows and Linux. A hot restart no longer leaves a second tray icon behind. On Linux the tray icon is a StatusNotifierItem and no longer needs libayatana-appindicator: the deb now depends on `libx11-6` and `libxi6` instead, and building needs `libx11-dev` and `libxi-dev`.
- Dependency updates: drift 2.35.2, drift_dev 2.35.1, shared_preferences 2.5.6, url_launcher 6.3.3, pocketbase 0.25.2, test 1.33.0, Gradle 9.8.0, and the pinned GitHub Actions (harden-runner 2.22.1, CodeQL 4.38.3, upload-artifact 7.0.2, download-artifact 8.0.2).

## [0.5.0] - 2026-10-16

### Added
- **Delete history** (*Settings → Data*): *Delete history on this device* removes every local clip, pinned ones too, and leaves the database alone; clips already there are not downloaded again. *Delete history in the database* removes every clip and deletion record from the connected database for all devices. Devices, pairing and keys stay, so sync carries on. In a signed group only the admin, or a member it gave the permission, can do this.
- **Pause a device** (*Settings → Devices → Manage devices*, admin only): a paused device stays paired and keeps its credentials but sends and receives nothing. Clips copied elsewhere while it is paused never reach it, and what it copies meanwhile stays on it. *Resume* brings it back. Unlike *Block*, it does not have to be paired again. Devices on 0.4.2 or older do not know this status and keep syncing.
- **Permissions and more admins** (*Manage devices*, admin of a signed group): *Permissions…* lets a member delete the database history without becoming an admin; *Make admin…* hands a paired device the group admin key, sealed to it, so it can manage the group too. Both are signed with the membership, so a member cannot grant them to itself. Supabase and PocketBase need two new device columns for this ([upgrade notes](docs/backends/supabase.md#upgrading-to-05)); without them the app refuses the grant and leaves the device unchanged.
- **Leave this group** and **Start a new group on this database** (*Settings → Devices*). Leaving removes this device from the group and forgets its credentials and keys; starting a new group wipes the database's clips and devices and makes this device the admin of a fresh group with new keys. The second is also the way back when the admin device is lost.
- **Sync with the database** switch (*Settings → Sync*): turns database sync off on this device only. Clipboard history keeps being recorded locally; nothing copied while it is off is sent, and clips from other devices arrive once it is back on.

### Changed
- **Universal Clipboard no longer relabels clips.** A copy that reached a Mac or iPhone through Apple's Universal Clipboard was recorded again on that device under its own name, and the original from the device that made it was then dropped as an echo, so every device showed the clip as its own. While syncing, Nija now leaves such copies to the device they came from (*Settings → Capture → Leave Universal Clipboard to its device*, on by default).
- **A clip can only be deleted from the group by the device that copied it.** On every other device the menu now says *Delete on this device* and only removes the local copy. Before, deleting another device's clip pushed a deletion signed with the wrong key: the database copy was emptied, but signed groups rejected the deletion, so other devices kept the clip and the device that copied it never saw the change. The sync engine now refuses to push such a deletion.
- **Dropping and recreating the database tables no longer disconnects every device.** A device whose row is missing now disconnects only if a device it already knew is still listed; otherwise the database was reset, and it registers again (the admin also signs its own row again), whichever device gets back first. Before, each device concluded it had been removed and deleted its credentials and passphrase.
- **Supabase with missing tables or columns** now reports *Connected* plus a schema check listing what is missing, and two ways to fix it. **Set up automatically** asks once for a Supabase personal access token and runs the setup through the Supabase Management API; the token is sent only to Supabase, for that one request, is never stored, and clipboard capture is paused while the dialog is open so copying it is not recorded. **Copy setup SQL** gives the same script to run by hand: generated for your table names and sign-in mode, it creates the tables or adds the missing columns, turns on row level security and enables realtime, and is safe to run again. Before, the app said *Connection failed: Could not find the table 'public.clip_items' in the schema cache*. Sync shows the same advice and retries until the tables exist.
- A keychain that times out is no longer read as "no keys": this device's signing keys are never replaced because of a slow keychain prompt (peers would reject every clip signed with new ones), and a credential delete the keychain did not confirm is retried rather than coming back on the next launch. Secret fields of the database form are read together, so a pending prompt costs one wait instead of one per field.
- Supabase personal access tokens (`sbp_…`) are recognised as credentials: *Skip keys and tokens* skips them and logs redact them.
- The macOS app renders with Skia instead of Impeller: on Flutter 3.47 Impeller dropped or garbled single letters in labels.
- **App Store and Mac App Store builds** (`STORE_BUILD=true`, set by `scripts/build_appstore.sh`) leave out the installers for other platforms and, in the sandboxed Mac build, *Start at login*. The script now also regenerates the Flutter config before the macOS archive (it used to ship the version of whatever was built last) and puts the provisioning profile on the Release configuration.
- On iPad and other wide layouts the side rail keeps clear of the status bar; the database tiles no longer overflow on 430 pt wide phones.
- Store screenshots are generated from the app itself: `test_screenshots/store_shots_test.dart` renders the screens with demo data, `tool/store_shots/compose.py` frames them.
- CI and release builds use Flutter 3.47.5 (from 3.44.4).

## [0.4.2] - 2026-09-30

### Added
- **Filters on the history list**: All, Text, Links, Images and Pinned. They combine with search.
- **Keyboard control on desktop.** The search field takes focus when the window opens and keeps it: the arrow keys move a selection through the list, Enter copies it, Shift+Enter previews it, `⌘1` to `⌘9` (Ctrl on Windows and Linux) copy by position, `⌘P` pins, `⌘⌫` deletes while the search is empty, and Esc clears the search and then hides the window. The keyboard button beside *Sync now* lists them.
- **Clip preview**: the whole clip, with character, word and line counts. *Copy as* puts a rewritten version on the clipboard (one line, trimmed, upper or lower case) without adding it to history. Open it from a clip's menu, with Shift+Enter, or by long-pressing on a phone.
- Search matches are highlighted in the list, and a clip that is only a colour code (`#2563eb`, `rgb(37 99 235)`) shows the colour instead of the text icon.
- **Recent clips in the tray menu**: the five newest, picked with one click. *Settings → Desktop → Recent clips in tray menu* turns it off.
- **Hide after copying** (*Settings → Desktop*): copying from history closes the window, so the hotkey, pick and paste loop needs no mouse.

## [0.4.1] - 2026-09-23

### Added
- **Every desktop installer is now launched before it is published.** Verification proved an installer contained the right app; it could not tell whether that app starts. `scripts/smoke_launch.sh` unpacks the dmg, deb and Windows zip, starts the binary hidden, and fails the release if it is not still running seconds later, the signature of a build that cannot find a library or dies initialising its database. Android and iOS are not covered: launching them needs an emulator or simulator, and the actions that provide one are not on this repository's allowlist.

## [0.4.0] - 2026-09-23

### Changed
- **The app is now called Nija.** निज (*nija*) is Sanskrit for "one's own"; the name says what the product is: your clipboard, on your database, under your keys. The About page and the README explain it. Nothing about how syncing, encryption or pairing works has changed.
- **Bundle identifiers are now `com.appfide.nija`** on every platform (from `com.appfide.clipboardSync` / `com.appfide.clipboard_sync`). The operating system treats a new identifier as a different app, so **0.3.0 will not upgrade in place**: install Nija, pair it as you would a new device, and remove the old app afterwards. Local history kept by the old install stays in its own sandbox and is not carried over; anything already in your database syncs back down on first run.
- **Pairing codes now start with `NIJA1.`** instead of `CSYNC1.`, and derive from a matching label. A device still running 0.3.0 cannot pair with one running this build: upgrade both.
- The repository, the Flutter app and the core package are now `appfide/nija`, `apps/nija` and `packages/nija_core`. Live-backend tests read `NIJA_TEST_<BACKEND>_*` environment variables instead of `CLIPSYNC_TEST_*`.
- Noto Sans Devanagari (SIL OFL 1.1) ships with the app so the name renders in its own script on every platform, not only where the OS happens to have a Devanagari face.

### Added
- **Every release is now verified before it is published.** `scripts/verify_artifacts.sh` opens each installer and checks it is the app it claims to be: bundle identifier `com.appfide.nija`, the version being released, a plausible binary size, and the signing state the release promises (Developer ID plus a notarization staple on macOS, a verified upload-key signature on Android). A build carrying the wrong identifier or last version's number now fails the release rather than reaching users.
- **Build provenance.** Every published file carries a GitHub-signed attestation naming the workflow, commit and runner that produced it: `gh attestation verify <file> --repo appfide/nija`. A checksum only proves a file is intact; provenance proves where it came from, which matters because whoever can replace the file can replace the checksum beside it.
- **An SPDX software bill of materials** ships with each release and is covered by `SHA256SUMS.txt`.
- Release notes now lead with the CHANGELOG section for that version instead of only a list of commit subjects.
- Releases are serialised: a second version bump queues behind the one in flight instead of racing it for the tag.

### Unchanged (deliberately)
- The passphrase-to-key derivation, the keyed content fingerprint and the key-envelope labels still carry their original `clipsync-*` v1 names. They are wire constants baked into data already sitting in users' databases: renaming them would make existing clips undecryptable and break de-duplication. The app's name is not part of its key schedule.

## [0.3.0] - 2026-09-22

### Added
- Android release builds are signed with an upload key when `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` are set, so installs can be upgraded in place. Earlier releases used the debug key, so upgrading from 0.2.1 or older needs an uninstall first.
- **Download page in the app**: *About → Get it on your other devices* (also linked from the pairing screen, where the other device may not have the app yet). It reads the newest GitHub release and lists every installer grouped by platform (macOS `.dmg`, Windows `.exe` and `.zip`, Linux `.deb` and AppImage, Android `.apk`, iOS `.ipa`), with file sizes, the caveat each one carries, a QR code per link for scanning from a phone, and a `SHA256SUMS.txt` link. It flags when the release is newer than the running build, and falls back to the releases page when GitHub cannot be reached. The lookup is unauthenticated, runs only while that page is open, and is the only request the app makes to anything but your own database.
- Release builds for macOS are signed with a Developer ID and notarized by Apple as soon as `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` exist as repository secrets, which removes the *"Apple could not verify…"* dialog on download. Without the secrets nothing changes: the build stays ad-hoc signed. Setup steps in [`docs/release.md`](docs/release.md#macos-signing-and-notarization).

### Security
- **The hash beside the ciphertext no longer leaks the clip.** Encrypted rows carried `content_hash` as a plain SHA-256 of the *plaintext*, so anyone who could read the database could confirm a guess or run a dictionary against short clips (one-time codes, passwords, card numbers), which is most of what end-to-end encryption is there to protect. Encrypted rows now carry `HMAC-SHA256` keyed from the group passphrase instead. De-duplication inside the group is unchanged, the local database still stores the plain hash, and the signature already covered the ciphertext, so nothing else moves.
- **Encrypted clips written before the fingerprint was keyed can be migrated.** Settings → Privacy counts them and rewrites `content_hash` to the keyed value, keeping the clip, its ciphertext and its timestamps. Detection is exact rather than heuristic: decrypt, hash the plaintext, and see whether that is what the row carries. Only the device that wrote a row can fix it, because a clip's signature is verified against the writing device's key.
- **Clips written before a group was encrypted are now findable and clearable.** Switching encryption on only ever sealed what came *next*; older rows stayed readable forever with nothing in the app saying so. Settings → Privacy now counts them and offers to clear them, which empties the stored text rather than only setting `deleted_at` (a tombstone that keeps its `content` column leaves the plaintext exactly where it was).
- Documented what a database holder can still see even with encryption on (device names, sizes, timestamps, the whole `devices` table) in [`docs/architecture.md`](docs/architecture.md#what-a-database-holder-can-still-see).

### Fixed
- **macOS: closing the window quit the app** instead of leaving it in the menu bar. `applicationShouldTerminateAfterLastWindowClosed` returned true, so the moment the window went away macOS ended the process, tray icon, background capture and all. It now returns false, and clicking the Dock icon with no window open brings the window back. Reopening from the tray icon or the global hotkey already worked.
- A database that cannot be resolved or reached now says so in words. Pairing, the devices list and the sync status used to print the raw transport error, `ClientException with SocketException: Failed host lookup: 'xxx.supabase.co' (OS Error: nodename nor servname provided, errno = 8), uri=…`, where a user needs to read "the database may have been deleted or the URL mistyped". The raw error still travels to the diagnostics export.

### Changed
- New app icon: a clipboard with a sync loop knocked out of it, on the blue tile the app already themes with. It replaces the stock Flutter icon on Android, iOS, macOS and Windows and the placeholder tray mark, and Android now ships an adaptive icon (gradient background, safe-zone foreground, themed monochrome layer) instead of one flat square. `scripts/gen_icons.py` renders every size from the vector sources in `design/icon/`; `--check` verifies the committed files still match.

## [0.2.1] - 2026-09-11

### Security
- Key rotation now issues envelopes only to the engine's rollback-aware trusted set. Before, a device whose *older* admin-signed row had been restored after a block (a rollback the engine already ignored for clips) could still receive the new passphrase. Found by running the attacker suite against a live Supabase project.

### Changed
- Live contract tests allow real websockets time to subscribe; new `live_attacker_test.dart` runs the signed-group threat model against a real database (`dart test -t live`).

## [0.2.0] - 2026-09-11

### Added
- **Secure by default**: choosing a database now encrypts the group with a random passphrase and signs it with an admin key (switch on the database screen); other devices receive the passphrase sealed through pairing. *Settings → Privacy → Show passphrase* reveals it for manual joins.
- **Device pairing**: Settings → Devices → *Add a device* shows a QR code (or a copyable code) plus an 8-digit PIN; the other device scans or pastes it under *Join another group* (also offered on the welcome screen). The code carries the database settings encrypted with the PIN (Argon2id → AES-256-GCM), is valid for 5 minutes and is never recorded in clipboard history. The host chooses the new device's role and access duration and whether to share the passphrase (delivered sealed to the new device, never inside the code).
- **Device management**: list every device with presence, block / unblock, remove, forget, change role (*Send & receive*, *Send only*, *Receive only*) and set temporary access. A blocked, removed or expired device stops itself, deletes its credentials, keys and passphrases, and tells the user. In a signed group these decisions are verified cryptographically; see `docs/devices.md`.
- **Send to…** in the history menu pushes a clip to one device only (`target_device_id`).
- **Capture filters**: *Pause capture* (also in the tray menu), *Skip password-manager content* (macOS concealed/transient pasteboard types, Windows `ExcludeClipboardContentFromMonitorProcessing`, Android 13+ `EXTRA_IS_SENSITIVE`; on by default) and *Skip keys and tokens* (credential-pattern heuristic).
- **Signed groups**: every device has an Ed25519 / X25519 identity; every clip is signed and verified against the sender's admin-signed key; membership changes (status, role, expiry, keys, admin flag, key envelope) are signed by a group admin key with rollback protection. Holding the database credentials is no longer enough to pose as a device, lift a block, or take over the group. *Settings → Devices → Secure this group* upgrades existing groups; members confirm the admin fingerprint once.
- **Encryption key rotation**: the admin issues a fresh random passphrase sealed to each verified device (X25519 + AES-GCM envelope covered by the admin signature). Removed or blocked devices cannot read clips sealed after the rotation; older history stays readable through a local keyring. Pairing delivers the passphrase the same way; it never travels inside the QR code.
- Device rows carry `status`, `role`, `expires_at`, `paired_by`, `app_version`, `sign_pub`, `box_pub`, `admin`, `admin_pub`, `membership_version`, `membership_sig`, `key_version`, `key_envelope`; clips carry `target_device_id`, `key_version`, `sig`. Supabase and PocketBase need the upgrade snippet in their guide; other backends need nothing.

### Changed
- Heartbeats write only presence fields, so a block set by another device is never overwritten.
- Local database schema v2 (adds `target_device_id`); migrates automatically.

## [0.1.0] - 2026-09-09

### Added
- Cross-platform clipboard sync for macOS, Windows, Linux, Android and iOS.
- Pluggable backends with their own schemas and settings forms: Supabase, PocketBase, CouchDB / Cloudant, Firebase Firestore (REST), MongoDB (driver), plus a local-only mode.
- Optional end-to-end encryption (Argon2id-derived AES-256-GCM); the database only ever stores ciphertext.
- Desktop: tray icon, global hotkey (`⌘⇧V` / `Ctrl+Shift+V`), start at login, background capture.
- Mobile: capture on resume and via the Capture action; guidance for the OS clipboard restrictions.
- Settings → Permissions with a live clipboard access test and per-platform instructions.
- Appearance setting (System / Light / Dark) and a `--theme=` launch flag.
- About page with project links and Appfide company details.
- Diagnostics screen with redacted, copyable logs.
- Automated release builds: dmg, exe + zip, deb + AppImage, apk + aab, unsigned ipa, with `SHA256SUMS.txt`.

### Security
- Threat model for multi-device groups documented in `docs/devices.md`, with an attacker test suite in `packages/nija_core/test/security`.
- Credentials live in the OS credential store with a bounded, non-blocking fallback; secrets are never logged (all log lines are redacted).
- Android app data excluded from cloud backup and device transfer.
- Repository gates: gitleaks + pre-commit locally, full-history secret scan in CI, SHA-pinned actions, branch and tag rulesets.

[Unreleased]: https://github.com/appfide/nija/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/appfide/nija/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/appfide/nija/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/appfide/nija/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/appfide/nija/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/appfide/nija/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/appfide/nija/releases/tag/v0.1.0
