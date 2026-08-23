#!/bin/bash
# Verify a generated appcast's EdDSA signature against the public key BAKED INTO THE BUILT APP,
# exactly as a Sparkle client will (#17).
#
# WHY THIS EXISTS: the release signs the zip with the SPARKLE_ED_PRIVATE_KEY secret, while clients
# verify with the SUPublicEDKey compiled into Info.plist. Nothing connected those two. If the secret
# is ever rotated, mistyped, or replaced with a different key, `generate_appcast` still succeeds and
# the release still publishes - and the break surfaces at the user's NEXT update, as a refused
# download, long after the release that caused it.
#
# `sign_update --verify` cannot catch this: it derives the public key from the same private key it
# was given, so it agrees with itself no matter which key that is.
#
# Usage: verify-appcast-signature.sh <app-bundle> <appcast.xml> <signed-archive>
set -euo pipefail

APP="${1:?usage: verify-appcast-signature.sh <app-bundle> <appcast.xml> <signed-archive>}"
APPCAST="${2:?missing appcast.xml}"
ARCHIVE="${3:?missing signed archive}"

for f in "$APP/Contents/Info.plist" "$APPCAST" "$ARCHIVE"; do
    test -e "$f" || { echo "verify-appcast-signature: no such file: $f" >&2; exit 1; }
done

PUBKEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
test -n "$PUBKEY" || {
    echo "verify-appcast-signature: the app ships no SUPublicEDKey - updates could never verify" >&2
    exit 1
}

# Pull the signature for THIS archive by basename, so a multi-item appcast cannot pass by matching
# some other item's signature.
ARCHIVE_NAME="$(basename "$ARCHIVE")"
SIGNATURE="$(python3 - "$APPCAST" "$ARCHIVE_NAME" <<'PY'
import sys, xml.etree.ElementTree as ET
appcast, want = sys.argv[1], sys.argv[2]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
for enc in ET.parse(appcast).getroot().iter("enclosure"):
    url = enc.get("url", "")
    if url.rsplit("/", 1)[-1] == want:
        print(enc.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature", ""))
        break
PY
)"
test -n "$SIGNATURE" || {
    echo "verify-appcast-signature: no edSignature for $ARCHIVE_NAME in $APPCAST" >&2
    exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An Ed25519 SPKI is a fixed 12-byte prefix followed by the raw 32-byte public key, so the base64
# SUPublicEDKey can be turned into something openssl will load without any extra tooling.
printf '302a300506032b6570032100' | xxd -r -p > "$WORK/spki.der"
printf '%s' "$PUBKEY" | base64 -d >> "$WORK/spki.der"
openssl pkey -pubin -inform DER -in "$WORK/spki.der" -out "$WORK/pub.pem" 2>/dev/null || {
    echo "verify-appcast-signature: SUPublicEDKey is not a valid Ed25519 public key" >&2
    exit 1
}
printf '%s' "$SIGNATURE" | base64 -d > "$WORK/sig.bin" 2>/dev/null || {
    echo "verify-appcast-signature: edSignature is not valid base64" >&2
    exit 1
}

if openssl pkeyutl -verify -rawin -pubin -inkey "$WORK/pub.pem" \
        -in "$ARCHIVE" -sigfile "$WORK/sig.bin" >/dev/null 2>&1; then
    echo "verify-appcast-signature: OK - $ARCHIVE_NAME verifies against the shipped SUPublicEDKey"
else
    echo "verify-appcast-signature: FAILED - $ARCHIVE_NAME does NOT verify against the app's" >&2
    echo "  SUPublicEDKey. The signing secret and the shipped public key are a different pair;" >&2
    echo "  publishing this would break updates for every existing user." >&2
    exit 1
fi
