# Releases

## How a release happens

1. Bump `version:` in `apps/nija/pubspec.yaml` (SemVer) and add a
   `CHANGELOG.md` entry in the same PR.
2. Merge to `main`. The **Release** workflow sees the new version, tags
   `v<version>`, builds every installer with `flutter_distributor`, verifies
   each one, and publishes a GitHub Release.
3. Pushing a `v*` tag by hand triggers the same pipeline.

Only one release runs at a time: a second version bump queues behind the first
rather than racing it for the tag.

### What the release ships

| File | What it is |
|---|---|
| The installers below | One per platform |
| `SHA256SUMS.txt` | Checksum of every file in the release, the SBOM included |
| `nija-<v>-sbom.spdx.json` | SPDX bill of materials for the whole repository |
| Build provenance | Attached to the release, not a file: signed by GitHub through the workflow's OIDC identity |

### Verifying a download

```sh
sha256sum -c SHA256SUMS.txt --ignore-missing     # integrity
gh attestation verify Nija-<v>-macos.dmg --repo appfide/nija   # origin
```

The attestation says which workflow, commit and runner produced that exact
file. A file that was rebuilt or tampered with anywhere between the runner and
the download fails this check, which a checksum alone cannot tell you, because
whoever replaces the file can replace the checksum next to it.

### The verification gate

Before anything is published, `scripts/verify_artifacts.sh` opens each
installer and checks that it is the app it claims to be: bundle identifier
`com.appfide.nija`, the version being released, a binary of plausible size, and
the signing state the release promises (Developer ID and a notarization staple
on macOS, a verified upload-key signature on Android). A build that ships the
wrong identifier or last version's number fails the release instead of reaching
users. Run it locally against a `dist/` directory the same way CI does:

```sh
scripts/verify_artifacts.sh macos 0.4.1 apps/nija/dist
```

### The smoke launch

Verification proves an installer holds the right app. It cannot say whether
that app *starts*: a build that cannot find a library, crashes in `main()` or
dies initialising its database passes every structural check ever written.
`scripts/smoke_launch.sh` unpacks the dmg, deb or Windows zip, starts the
binary with `--hidden`, and fails the release unless it is still running
several seconds later, printing whatever the process wrote before it died.

```sh
scripts/smoke_launch.sh linux apps/nija/dist    # needs xvfb for the GTK build
```

Android and iOS are not covered. Launching either needs an emulator or a
simulator, and the actions that provide one are not on this repository's
Actions allowlist, which is worth more than the coverage. Both are still
verified structurally, and the Android APK's signature is checked against its
upload key.

| Platform | Artifact | Signed? |
|---|---|---|
| macOS | `Nija-<v>-macos.dmg` (arm64; Intel Macs run it via Rosetta) | Developer ID + notarized once the Apple secrets are set (below); ad-hoc otherwise |
| Windows | `…-windows.exe` (Inno Setup) + `.zip` portable | No: see [Windows signing](#windows-signing) |
| Linux | `…-linux.deb`, `…-linux.AppImage` (x86_64) | n/a |
| Android | `…-android.apk`, `.aab` | Debug key unless secrets set |
| iOS | `Nija-<v>-ios-unsigned.ipa` | No: sideload with AltStore/Sideloadly or re-sign |

## Installing unsigned builds

- **macOS keychain prompt**: unsigned builds get a new ad-hoc signature every release, so after an update macOS asks to allow access to the stored credentials, click *Always Allow*. Signing with a Developer ID (below) makes the signature stable and removes the prompt.

- **macOS**: right-click the app → *Open* → *Open*; or
  `xattr -dr com.apple.quarantine "/Applications/Nija.app"`.
- **Windows**: SmartScreen → *More info* → *Run anyway*.
- **iOS**: unsigned `.ipa` requires a sideloading tool with your own Apple ID.

## Adding signing (repository secrets)

| Secret | Purpose |
|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release-sign APK/AAB. Generate: `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`, then `base64 -i upload-keystore.jks`. Without these, CI signs with the debug key, installable, but users cannot upgrade in place across releases. |
| `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | Developer ID signing + notarization. Wired; see [macOS signing and notarization](#macos-signing-and-notarization) for how to produce each one. All five must be present, the workflow skips signing entirely if `MACOS_CERT_P12_BASE64` is empty. |

Never commit any of these files. `.gitignore`, gitleaks and `scripts/verify_secrets.sh` all reject them.

## macOS signing and notarization

### Setting it up

The certificate has to be created by hand in Apple's portal; everything either
side of that is scripted.

1. `scripts/` already holds a key and CSR if one was prepared for you
   (`~/nija-developer-id.key`, `~/nija-developer-id.csr`). Otherwise:

   ```sh
   umask 077
   openssl req -new -newkey rsa:2048 -nodes \
     -keyout ~/nija-developer-id.key -out ~/nija-developer-id.csr \
     -subj "/emailAddress=<your-apple-id>/CN=Appfide Private Limited/O=Appfide Private Limited/C=IN"
   ```

   The `.key` is the half Apple never sees and cannot reissue. Keep it off the
   repo and off any share; losing it means revoking the certificate and
   starting over.

2. At [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/add),
   choose **Developer ID Application**, upload `nija-developer-id.csr`, and
   download the `.cer`. It must be *Developer ID Application*: a Mac App
   Distribution or Apple Development certificate cannot sign software
   distributed outside the App Store, which is the only kind this project ships.

3. Create an app-specific password at
   [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security →
   App-Specific Passwords. Notarization refuses an ordinary Apple ID password.

4. Run:

   ```sh
   scripts/setup_macos_signing.sh ~/Downloads/developerID_application.cer
   ```

   It checks the certificate is the right kind and actually matches the private
   key (a mismatch otherwise surfaces as an unexplained signing failure in CI
   months later), then builds the `.p12` with a generated password and sets all
   five secrets through `gh`. Nothing is printed.

The next release signs and notarizes the dmg. The verification step fails the
release if the Developer ID signature or the notarization staple is missing, so
a silent fallback to ad-hoc signing cannot ship.

### Background

Without this, macOS shows *"Apple could not verify 'Nija.app' is free
of malware"* and the only way in is right-click → *Open* or stripping the
quarantine attribute. Removing that dialog needs a **paid Apple Developer
Program membership** ($99/year): there is no free path, and ad-hoc signing does
not help. Everything else below is a one-time setup; after it, every release is
signed and notarized automatically.

Enrol as an individual and the Gatekeeper dialog shows your own name; enrolling
as the Appfide organisation (needs a D-U-N-S number) makes it show *Appfide*.

1. **Certificate.** Xcode → *Settings* → *Accounts* → your Apple ID → *Manage
   Certificates* → **+** → *Developer ID Application*. It lands in the login
   keychain.
2. **Export it.** Keychain Access → *login* → *My Certificates* → right-click
   *Developer ID Application: …* → *Export* → `.p12`, and set a password. Both
   the private key and the certificate must be in the export (expand the row,
   it should have a key under it).
3. **Encode it.** `base64 -i certificate.p12 | pbcopy`, then delete the `.p12`;
   `.gitignore`, gitleaks and `scripts/verify_secrets.sh` all reject it, but it
   should not sit on disk either.
4. **Team ID.** [developer.apple.com/account](https://developer.apple.com/account)
   → *Membership details* → *Team ID* (10 characters).
5. **App-specific password** for notarization:
   [appleid.apple.com](https://appleid.apple.com) → *Sign-In and Security* →
   *App-Specific Passwords* → **+**. This is not your Apple ID password.
6. **Add the secrets** (repo → *Settings* → *Secrets and variables* → *Actions*,
   or the CLI):

   ```sh
   base64 -i certificate.p12 | gh secret set MACOS_CERT_P12_BASE64
   gh secret set MACOS_CERT_PASSWORD    # the .p12 export password
   gh secret set APPLE_ID               # the Apple ID email
   gh secret set APPLE_TEAM_ID          # 10-character team id
   gh secret set APPLE_APP_PASSWORD     # app-specific password
   ```

What the release workflow then does, all on the macOS runner:

- imports the `.p12` into a throwaway keychain and writes
  `macos/Runner/Configs/Signing.xcconfig`, which switches the Release build to
  manual signing with the Developer ID identity, the hardened runtime and a
  secure timestamp;
- builds and packages the dmg as usual, so every framework inside the bundle is
  signed by Xcode's own embed phase;
- signs the dmg, submits it to Apple with `notarytool --wait`, and prints the
  notary log if the verdict is anything but `Accepted`;
- staples the ticket to the dmg and runs `spctl --assess`, which is the check
  the user's Mac performs;
- deletes the keychain and the xcconfig, whether or not the job succeeded.

Notarization usually takes a few minutes but Apple gives no guarantee, so the
macOS job can sit waiting for a while. The certificate is valid for five years;
the app-specific password lasts until you revoke it.

Two things that follow from a stable signature: macOS stops asking to allow
keychain access after every update, and the dmg can be opened by double-clicking
like any other app.

## Windows signing

Not wired, and not a `.pfx` in a secret any more: since June 2023 public CAs
must keep Authenticode keys on an HSM or hardware token, so there is no file to
base64. The realistic options are [Azure Trusted
Signing](https://learn.microsoft.com/azure/trusted-signing/) (about $10/month,
designed for CI, individual accounts allowed) or an EV certificate on a cloud
HSM (a few hundred dollars a year). SmartScreen also warms up on its own as a
given binary gets downloaded.

Until then the installer shows *Windows protected your PC* → *More info* →
*Run anyway*.

## Local packaging

```sh
dart pub global activate flutter_distributor
cd apps/nija
flutter_distributor release --name local-macos      # dmg (needs `npm i -g appdmg`)
flutter_distributor release --name local-linux      # deb + AppImage (needs appimagetool)
flutter_distributor release --name local-windows    # exe (needs Inno Setup) + zip
flutter_distributor release --name local-android    # apk + aab
```
