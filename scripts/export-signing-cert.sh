#!/bin/bash
# Export the Developer ID signing identity and load it into the two GitHub secrets that
# .github/workflows/release.yml hard-fails without (#17).
#
# WHY THIS IS A SCRIPT AND NOT A DOCUMENTED PROCEDURE: TermTile set these same two secrets on
# 2026-07-15 and recorded only their NAMES, never how the .p12 was produced. The knowledge left
# with the session. This file is that procedure, executable.
#
# YOU RUN THIS, not an agent: `security export` raises a Keychain dialog, and the password it wants
# is your MAC LOGIN PASSWORD (the one that unlocks this Mac) - NOT your Apple ID password. Keychain
# never accepts the Apple ID one. Expect to click Allow once or twice.
#
# The .p12 password is generated here at random and goes straight into the GitHub secret. No
# credential of yours is ever printed, stored, or passed through an agent.
set -euo pipefail

REPO="${REPO:-EvanCNavarro/PushText}"
IDENTITY_HINT="Developer ID Application"
WORK="$(mktemp -d)"
# Trap on EXIT, not on success: the .p12 and the password file must not survive a failure either.
trap 'rm -rf "$WORK"' EXIT

echo "==> Checking the identity exists before prompting you for anything"
if ! security find-identity -v -p codesigning | grep -q "$IDENTITY_HINT"; then
    echo "No '$IDENTITY_HINT' identity in the login keychain - nothing to export." >&2
    exit 1
fi
security find-identity -v -p codesigning | grep "$IDENTITY_HINT"

P12="$WORK/signing.p12"
P12_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 40)"

echo
echo "==> A Keychain dialog is about to appear."
echo "    Enter your MAC LOGIN PASSWORD. Not your Apple ID password."
echo
security export -k "$HOME/Library/Keychains/login.keychain-db" \
    -t identities -f pkcs12 -P "$P12_PASSWORD" -o "$P12"

# Prove the artifact before uploading it. An export that "succeeded" but produced a .p12 without the
# Developer ID cert, or without its private key, would set both secrets to something that fails only
# at release time - the exact class of green this repo does not accept.
echo "==> Verifying the exported .p12 actually contains the identity"
INFO="$(openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys -info 2>&1 || true)"
echo "$INFO" | grep -q "$IDENTITY_HINT" || {
    echo "The .p12 does not contain a '$IDENTITY_HINT' certificate - refusing to upload it." >&2
    exit 1
}
# Assert the key IS PRESENT rather than that openssl exited 0: `-nocerts -noout` returns 0 on a
# .p12 that contains no private key at all. Caught by planting a keyless .p12, which this guard
# accepted before the grep was added.
openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nocerts -nodes 2>/dev/null \
    | grep -q "PRIVATE KEY" || {
    echo "The .p12 has no private key - CI could import it and still fail to sign." >&2
    exit 1
}
echo "    ok: certificate and private key both present"

echo "==> Setting the two repo secrets on $REPO"
base64 -i "$P12" | gh secret set PUSHTEXT_RELEASE_SIGNING_CERT_P12_BASE64 --repo "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set PUSHTEXT_RELEASE_SIGNING_CERT_PASSWORD --repo "$REPO"

echo
echo "Done. Both secrets set; the .p12 and its password are being deleted now."
gh secret list --repo "$REPO"
