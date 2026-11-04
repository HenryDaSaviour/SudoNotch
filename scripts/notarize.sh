#!/bin/bash
# Signs with Developer ID, notarizes with Apple, and staples the ticket to dist/SudoNotch.dmg.
# One-time setup (run by the account owner, it asks for their key details):
#   xcrun notarytool store-credentials pseudonotch --key ~/Downloads/AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
set -euo pipefail
cd "$(dirname "$0")/.."
# Your "Developer ID Application" certificate (see: security find-identity -v -p codesigning)
: "${SIGN_ID:?set SIGN_ID to your Developer ID Application certificate name or hash}"
export SIGN_ID
PROFILE="${1:-pseudonotch}"
./scripts/build.sh --dmg
xcrun notarytool submit dist/SudoNotch.dmg --keychain-profile "$PROFILE" --wait
xcrun stapler staple dist/SudoNotch.dmg
xcrun stapler validate dist/SudoNotch.dmg
spctl -a -t open --context context:primary-signature -vv dist/SudoNotch.dmg
