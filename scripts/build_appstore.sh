#!/usr/bin/env bash
# Builds and uploads an App Store / TestFlight build.
#
#   scripts/build_appstore.sh ios   [--upload]
#   scripts/build_appstore.sh macos [--upload]
#
# Without --upload it stops after producing a signed .ipa or .pkg, so the
# artifact can be inspected before anything reaches Apple.
#
# Credentials come from the App Store Connect API key, never from a password:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH
# which are read from $ASC_ENV_FILE if set (default: the appstore-translator
# .env next to this repository).
#
# Signing is manual on purpose. Cloud-managed signing needs an API key with
# admin rights over distribution certificates; this instead uses the Apple
# Distribution certificate already in the keychain plus a profile created
# ahead of time in App Store Connect.
#
# Both platforms build with STORE_BUILD=true, which hides the installers for
# other platforms and (sandboxed) start-at-login; see BuildInfo.storeBuild.
#
# macOS note: the Mac App Store requires the sandbox, which the Developer ID
# build deliberately does not use. The Runner target is therefore switched to
# AppStore.entitlements for the archive and switched back afterwards, even if
# the build fails. Start-at-login is inert in a sandboxed build until it moves
# from a LaunchAgent to SMAppService.
set -euo pipefail

platform="${1:?ios or macos required}"
upload=false
[ "${2:-}" = "--upload" ] && upload=true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/apps/nija"
OUT="${BUILD_OUT:-$ROOT/build/appstore}"
TEAM_ID="P4UH33447Z"
BUNDLE_ID="com.appfide.nija"
ASC_ENV_FILE="${ASC_ENV_FILE:-$ROOT/../../Internal/appstore-translator/.env}"

fail() { echo "error: $*" >&2; exit 1; }

# Values in that .env carry trailing comments.
getenv_value() {
  [ -f "$ASC_ENV_FILE" ] || fail "no App Store Connect env file at $ASC_ENV_FILE"
  grep "^$1=" "$ASC_ENV_FILE" | head -1 | cut -d= -f2- | sed -E 's/[[:space:]]*#.*$//' | tr -d ' "'
}

version=$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' "$APP_DIR/pubspec.yaml")
[ -n "$version" ] || fail "could not read version from pubspec.yaml"
sha=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)
mkdir -p "$OUT"

echo "building $platform $version ($sha)"

case "$platform" in
  ios)
    (cd "$APP_DIR" && flutter build ipa --release \
      --export-method app-store \
      --dart-define "APP_VERSION=$version" --dart-define "GIT_SHA=$sha" \
      --dart-define STORE_BUILD=true \
      --no-tree-shake-icons >/dev/null) || true

    cat > "$OUT/ExportOptions-ios.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE_ID</key><string>Nija iOS App Store</string></dict>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict></plist>
EOF
    rm -rf "$OUT/ios"
    xcodebuild -exportArchive \
      -archivePath "$APP_DIR/build/ios/archive/Runner.xcarchive" \
      -exportOptionsPlist "$OUT/ExportOptions-ios.plist" \
      -exportPath "$OUT/ios" >/dev/null
    artifact="$OUT/ios/Nija.ipa"
    ;;

  macos)
    pbx="$APP_DIR/macos/Runner.xcodeproj/project.pbxproj"
    backup="$OUT/project.pbxproj.before-appstore"
    cp "$pbx" "$backup"
    # Restore the Developer ID configuration no matter how this exits.
    trap 'cp "$backup" "$pbx"; echo "restored the Developer ID build configuration"' EXIT

    python3 - "$pbx" "$TEAM_ID" <<'PY'
import sys, pathlib
pbx, team = pathlib.Path(sys.argv[1]), sys.argv[2]
s = pbx.read_text()
old = '''\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;'''
new = f'''\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/AppStore.entitlements;
\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tDEVELOPMENT_TEAM = {team};'''
if old not in s:
    raise SystemExit('the Runner Release configuration is not in the expected shape')
s = s.replace(old, new, 1)
# The profile must go on the same (Release) configuration, which comes after
# the Debug and Profile ones in the file: replacing the first match would set
# it on Profile and leave the archive without one.
at = s.index(new)
spec = '\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "";'
i = s.find(spec, at)
end = s.find('name = Release;', at)
if i < 0 or i > end:
    raise SystemExit('no PROVISIONING_PROFILE_SPECIFIER in the Runner Release configuration')
s = s[:i] + '\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "Nija macOS App Store";' + s[i + len(spec):]
pbx.write_text(s)
PY

    cat > "$OUT/ExportOptions-macos.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key>
  <dict><key>$BUNDLE_ID</key><string>Nija macOS App Store</string></dict>
  <key>destination</key><string>export</string>
</dict></plist>
EOF
    rm -rf "$OUT/macos" "$OUT/Nija-macos.xcarchive"
    # xcodebuild archives from the Flutter config of the last `flutter build
    # macos` (version, build number, dart-defines). Regenerate it so the
    # archive carries this version rather than whatever ran before.
    (cd "$APP_DIR" && flutter build macos --release \
      --dart-define "APP_VERSION=$version" --dart-define "GIT_SHA=$sha" \
      --dart-define STORE_BUILD=true >/dev/null)
    (cd "$APP_DIR/macos" && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
      -configuration Release -archivePath "$OUT/Nija-macos.xcarchive" archive >/dev/null)
    xcodebuild -exportArchive \
      -archivePath "$OUT/Nija-macos.xcarchive" \
      -exportOptionsPlist "$OUT/ExportOptions-macos.plist" \
      -exportPath "$OUT/macos" >/dev/null
    artifact="$OUT/macos/Nija.pkg"
    ;;

  *)
    fail "unknown platform $platform (expected ios or macos)"
    ;;
esac

[ -f "$artifact" ] || fail "no artifact produced at $artifact"
echo "built $(basename "$artifact") ($(du -h "$artifact" | cut -f1))"

if [ "$upload" != true ]; then
  echo "not uploading (pass --upload to send it to App Store Connect)"
  exit 0
fi

key_id=$(getenv_value ASC_KEY_ID)
issuer=$(getenv_value ASC_ISSUER_ID)
[ -n "$key_id" ] && [ -n "$issuer" ] || fail "ASC_KEY_ID and ASC_ISSUER_ID must be set"

# iTMSTransporter reads the key from ~/private_keys by ID.
key_src=$(getenv_value ASC_PRIVATE_KEY_PATH)
key_src="$(cd "$(dirname "$ASC_ENV_FILE")" && cd "$(dirname "$key_src")" && pwd)/$(basename "$key_src")"
mkdir -p ~/private_keys
cp "$key_src" ~/private_keys/"AuthKey_$key_id.p8"
chmod 600 ~/private_keys/"AuthKey_$key_id.p8"

echo "uploading to App Store Connect..."
xcrun iTMSTransporter -m upload -assetFile "$artifact" \
  -apiKey "$key_id" -apiIssuer "$issuer" 2>&1 \
  | grep -iE "error|warning|uploaded successfully|package summary" || true

echo "done. The build appears in TestFlight once Apple finishes processing it."
