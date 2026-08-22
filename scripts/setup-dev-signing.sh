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
# NOTE the missing -v, here and below. `find-identity -v` lists only TRUSTED identities, and a
# self-signed cert is never trusted - it shows as CSSMERR_TP_NOT_TRUSTED. codesign can still sign
# with it perfectly well (measured: Authority=PushText Dev Signing, exit 0), so -v was asserting the
# wrong post-condition and made a working identity look absent.
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
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
# PKCS#12 algorithm choice is NOT cosmetic - measured on this machine, OpenSSL 3.6.3:
#   default (AES-256-CBC keys, SHA-256 MAC) -> security: "MAC verification failed ... (wrong password?)"
#   -legacy (3DES keys, RC2 certs)          -> same failure; modern macOS rejects RC2 outright
#   3DES for BOTH bags + SHA-1 MAC          -> "1 identity imported."
# An empty password also fails, independently of the algorithms, so a real one is used and is not a
# secret: the p12 is created, imported and deleted inside one mktemp dir within this script.
P12_PASSWORD="pushtext-dev-signing"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" \
  -passout "pass:$P12_PASSWORD" -name "$IDENTITY" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
# -A: any app may use the key (no per-use ACL prompt); -T codesign: explicitly allow codesign.
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$P12_PASSWORD" -A -T /usr/bin/codesign

# Verify the POST-CONDITION, not the attempt: actually sign something with it. Presence in the
# keychain is not proof that codesign will accept it.
PROBE="$TMP/signing-probe"
printf '#!/bin/sh\nexit 0\n' > "$PROBE"
chmod +x "$PROBE"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY" \
   && codesign --force --sign "$IDENTITY" "$PROBE" >/dev/null 2>&1; then
  echo "[OK] '$IDENTITY' created and proven by a test signature."
  echo "     Rebuild with scripts/build-app.sh - it auto-detects + signs with it."
else
  echo "[ERROR] Import did not register a codesigning identity. If the login keychain was locked, unlock it"
  echo "  and re-run; or create the cert via Keychain Access -> Certificate Assistant -> Create a"
  echo "  Certificate (name '$IDENTITY', type Code Signing)."
  exit 1
fi
