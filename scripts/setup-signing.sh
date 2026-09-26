#!/bin/bash
#
# Creates a self-signed code-signing certificate for local development.
#
# Why this exists
# ---------------
# macOS TCC (the permissions system) remembers a grant against the app's *designated
# requirement*. With ad-hoc signing (`codesign --sign -`) that requirement is literally
# the binary's cdhash:
#
#     # designated => cdhash H"5ee7c0de885e..."
#
# So every rebuild produces a new identity and silently invalidates every permission the
# app was granted — Microphone and Accessibility alike. The System Settings checkbox
# stays visibly on while `AXIsProcessTrusted()` returns false, which is maximally
# confusing.
#
# Signing with a real (even self-signed) certificate instead produces a requirement based
# on the bundle ID and the signing certificate:
#
#     # designated => identifier "com.talktomymac.dictate" and certificate leaf = H"..."
#
# That is stable across rebuilds, so permissions granted once keep working.
#
# This needs your login password: macOS will not let a certificate be marked trusted for
# code signing without authorization. Nothing here requires sudo.
#
# Re-running is safe — it detects an existing identity and exits early.

set -euo pipefail

CERT_NAME="TalkToMyMac Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "✅ Signing identity \"$CERT_NAME\" already exists and is valid. Nothing to do."
    security find-identity -v -p codesigning | grep -F "$CERT_NAME"
    exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
P12_PASS="$(openssl rand -hex 16)"

echo "==> Generating a self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$CERT_NAME/O=TalkToMyMac" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Apple's Security framework rejects OpenSSL 3's default PKCS#12 algorithms, so pin the
# legacy ones it can actually read.
openssl pkcs12 -export -out "$WORK_DIR/ident.p12" \
    -inkey "$WORK_DIR/key.pem" -in "$WORK_DIR/cert.pem" \
    -name "$CERT_NAME" -passout "pass:$P12_PASS" \
    -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES 2>/dev/null

echo "==> Importing into your login keychain…"
# -T grants codesign access to the private key, -A avoids a keychain prompt per build.
security import "$WORK_DIR/ident.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -A

echo "==> Marking it trusted for code signing (this is the step that needs your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/cert.pem"

echo
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
    echo "✅ Done. Identity is valid:"
    security find-identity -v -p codesigning | grep -F "$CERT_NAME"
    echo
    echo "Next steps:"
    echo "  1. make build          # will now sign with this identity automatically"
    echo "  2. In System Settings → Privacy & Security, REMOVE any existing TalkToMyMac"
    echo "     entries under Accessibility and Microphone (they point at the old ad-hoc"
    echo "     identity), then relaunch the app and grant when prompted."
    echo "  3. Permissions will now survive future rebuilds."
else
    echo "⚠️  The certificate was created but is not reporting as valid."
    echo "    Open Keychain Access, find \"$CERT_NAME\", get info, expand Trust, and set"
    echo "    \"Code Signing\" to \"Always Trust\"."
    exit 1
fi
