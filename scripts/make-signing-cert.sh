#!/bin/bash
# One-time: create a self-signed code-signing identity "Onyx Local Signing" so every `make app`
# has the same signature and Keychain "Always Allow" sticks. Idempotent. Run it yourself in
# Terminal: it asks once for your login-keychain password so codesign may use the key silently.
#   scripts/make-signing-cert.sh            # login keychain
#   KEYCHAIN=/tmp/x.keychain-db KEYCHAIN_PASSWORD=pw scripts/make-signing-cert.sh   # tests
set -euo pipefail
NAME="Onyx Local Signing"
KC="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then echo "already have \"$NAME\""; exit 0; fi
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat > "$T/cfg" <<CFG
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$T/cfg" -keyout "$T/key.pem" -out "$T/cert.pem" 2>/dev/null
P=$(openssl rand -hex 12)
openssl pkcs12 -export -legacy -inkey "$T/key.pem" -in "$T/cert.pem" -name "$NAME" -out "$T/id.p12" -passout "pass:$P" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -name "$NAME" -out "$T/id.p12" -passout "pass:$P"
security import "$T/id.p12" -k "$KC" -P "$P" -T /usr/bin/codesign >/dev/null
# Let Apple's codesign use the key without a dialog (asks for the keychain password unless given).
if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" -l "$NAME" "$KC" >/dev/null
else
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" "$KC" >/dev/null
fi
echo "created \"$NAME\" in $KC"
