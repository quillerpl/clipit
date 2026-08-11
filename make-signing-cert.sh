#!/bin/bash
# One-time setup: create a self-signed code-signing certificate named "Magwell Dev" in your
# login keychain, so Magwell keeps a STABLE code identity across rebuilds.
#
# Why this is needed
#   macOS ties the Accessibility permission to an app's code signature. An ad-hoc signature
#   (the fallback build.sh uses) gets a brand new hash on every single build, so the grant you
#   gave yesterday points at a binary that no longer exists — the System Settings switch stays
#   visibly ON while the app is actually denied.
#
#   Signing with a certificate changes the app's designated requirement from a per-build hash to
#       identifier "com.jacks.magwell" and certificate leaf = H"<fixed hash>"
#   which does not change when you rebuild. So the grant sticks.
#
# What this touches
#   Creates a 2048-bit key + self-signed certificate (valid 10 years) in your login keychain.
#   It does NOT add a trusted root and does NOT change any system trust settings — codesign
#   is happy to use an untrusted self-signed certificate, and TCC only cares that the leaf
#   hash stays the same. Nothing here should ask for your password.
#
# To undo:  security delete-identity -c "Magwell Dev"

set -euo pipefail

NAME="Magwell Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Transport passphrase for the intermediate PKCS#12 only. It is never stored: the file lives
# in a temp dir for one command and is deleted on exit. It must be non-empty — Security
# .framework cannot verify the MAC on an empty-password PKCS#12 written by OpenSSL 3.
P12_PASS="magwell-transport"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "'$NAME' already exists in your login keychain — nothing to do."
    echo "Rebuild with ./build.sh and it will be used automatically."
    exit 0
fi

echo "==> Generating key and self-signed certificate"
cat > "$WORK/openssl.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Magwell Dev

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# OpenSSL 3 defaults to PBE algorithms that macOS's importer rejects with a misleading
# "MAC verification failed (wrong password?)". Pin the legacy SHA1/3DES set it can read.
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/bundle.p12" \
    -passout "pass:$P12_PASS" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> Importing into your login keychain"
# -T /usr/bin/codesign puts codesign on the key's ACL, so builds don't raise a keychain dialog.
security import "$WORK/bundle.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

echo
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "'$NAME' is ready."
    echo
    echo "Next:"
    echo "  ./build.sh"
    echo "  then grant Accessibility to /Applications/Magwell.app once — it will stick."
    echo
    echo "Note: 'security find-identity -v -p codesigning' will still report 0 valid"
    echo "identities, because the certificate is not a trusted root. That is expected and"
    echo "harmless — codesign uses it regardless, which is why no password was needed."
else
    echo "Import reported success but the certificate isn't in the keychain. Stop and check"
    echo "Keychain Access → login → Certificates before rebuilding."
    exit 1
fi
