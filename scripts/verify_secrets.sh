#!/usr/bin/env bash
# Secondary secret gate that complements gitleaks with project-specific checks:
#   1. Refuses credential-bearing file names regardless of content.
#   2. Refuses hardcoded remote endpoints inside application code; every DB
#      URL must come from user settings, never from source.
#   3. Refuses obvious "TODO remove key" style leftovers.
# Usage: scripts/verify_secrets.sh [files...]   (no args = scan whole tree)
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -t files < <(git ls-files 2>/dev/null || find . -type f -not -path './.git/*')
fi

status=0

forbidden_name='(^|/)(\.env(\.[^/]+)?|key\.properties|google-services\.json|GoogleService-Info\.plist|firebase_options\.dart|service-account[^/]*\.json)$|\.(jks|keystore|p12|p8|pem|mobileprovision|cer|certSigningRequest)$'
forbidden_name_allow='(^|/)\.env\.example$'

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  if [[ "$f" =~ $forbidden_name ]] && ! [[ "$f" =~ $forbidden_name_allow ]]; then
    echo "::error file=$f::credential file must not be committed"
    status=1
  fi
done

# Hardcoded endpoints in app/core source (docs, tests and fixtures are exempt).
# `supabase\.co` must not run on into `supabase.com` (Supabase's own API and
# docs, which are not a user's project).
endpoint_re='https?://[a-z0-9-]+\.(supabase\.co([^a-z]|$)|firebaseio\.com|pocketbase\.io|cloudant\.com|mongodb\.net)'
endpoint_allow='(^|/)(test|tests|integration_test|example|docs)/|\.md$|_test\.dart$|(^|/)\.gitleaks\.toml$|(^|/)scripts/'
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  [[ "$f" =~ \.(dart|kt|swift|cc|cpp|h|yaml|yml|json|toml|xml|plist)$ ]] || continue
  [[ "$f" =~ $endpoint_allow ]] && continue
  if grep -nE "$endpoint_re" "$f" >/dev/null 2>&1; then
    grep -nE "$endpoint_re" "$f" | while IFS= read -r line; do
      echo "::error file=$f::hardcoded backend endpoint (must come from settings): $line"
    done
    status=1
  fi
done

# Leftover markers.
marker_re='(REMOVE[ _-]?BEFORE[ _-]?COMMIT|DO[ _-]?NOT[ _-]?COMMIT|NOCOMMIT)'
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  [[ "$f" == scripts/verify_secrets.sh ]] && continue
  if grep -nEi "$marker_re" "$f" >/dev/null 2>&1; then
    echo "::error file=$f::contains a do-not-commit marker"
    status=1
  fi
done

exit $status
