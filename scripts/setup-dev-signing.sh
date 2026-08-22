#!/bin/bash
# One-time local dev signing setup (#13c). Creates a STABLE self-signed code-signing identity
# ("PushText Dev Signing") in the login keychain so `build-app.sh` signs with a constant code identity.
# Why: ad-hoc signing ("-") produces a fresh cdhash every build, which silently RESETS every macOS TCC
# grant (Accessibility, Input Monitoring) on each rebuild - you'd re-approve PushText after every build.
# A stable identity keeps the grants; you approve once and they persist across rebuilds.
#
# This does NOT help distribution - real users need Developer ID + notarization (the v0.5.0 milestone).
# It only stabilizes LOCAL dev builds. Idempotent: no-op if the identity already exists.
#
# macOS may prompt to unlock your login keychain during import, and codesign may prompt "Always Allow"
# on first use - that's expected (a one-time click), and cheaper than re-granting permissions forever.
set -euo pipefail

IDENTITY="PushText Dev Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "[OK] '$IDENTITY' already present - nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -config "$TMP/req.cnf"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
  -passout pass: -name "$IDENTITY"
# -A: any app may use the key (no per-use ACL prompt); -T codesign: explicitly allow codesign.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -A -T /usr/bin/codesign

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "[OK] '$IDENTITY' created. Rebuild with scripts/build-app.sh - it auto-detects + signs with it."
else
  echo "[ERROR] Import did not register a codesigning identity. If the login keychain was locked, unlock it"
  echo "  and re-run; or create the cert via Keychain Access -> Certificate Assistant -> Create a"
  echo "  Certificate (name '$IDENTITY', type Code Signing)."
  exit 1
fi
