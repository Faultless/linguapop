#!/usr/bin/env bash
# Sign the CI-built APKs for a release, and publish them.
#
# The APKs must come from the "Release APKs" GitHub Actions workflow, not from
# a local `flutter build`: F-Droid compares its own build of the tagged commit
# against the binary published here, and only a Linux x86_64 build stands a
# chance of matching. See .github/workflows/release-apks.yml.
#
# Signing is done here rather than in CI so the key never leaves this machine.
# `apksigner` adds a signing block and leaves every zip entry untouched, which
# is the part F-Droid compares — verified by `tool/check_reproducible.py`.
#
# Usage:
#   tool/sign_release.sh <run-id> <version>       # e.g. 33381467406 7.4.1
#
# Requires: gh, apksigner (Android build-tools), android/key.properties.
set -euo pipefail

RUN_ID="${1:?usage: sign_release.sh <workflow-run-id> <version>}"
VERSION="${2:?usage: sign_release.sh <workflow-run-id> <version>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PROPS="$REPO_ROOT/android/key.properties"
[ -f "$KEY_PROPS" ] || { echo "missing $KEY_PROPS — see ~/Documents/'LinguaPop Signing Key'/'READ ME FIRST.md'"; exit 1; }

APKSIGNER="$(ls "$HOME"/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | tail -1)"
[ -x "$APKSIGNER" ] || { echo "apksigner not found"; exit 1; }

# shellcheck disable=SC2046
eval "$(grep -E '^(storeFile|storePassword|keyAlias|keyPassword)=' "$KEY_PROPS" | sed 's/^/KP_/')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "== downloading artifacts from run $RUN_ID"
gh run download "$RUN_ID" -D "$WORK/dl" >/dev/null
SRC="$(find "$WORK/dl" -name 'app-*-release.apk' -exec dirname {} \; | head -1)"
[ -n "$SRC" ] || { echo "no APKs in that run's artifacts"; exit 1; }

mkdir -p "$WORK/signed"
declare -a ASSETS=()
for abi in armeabi-v7a arm64-v8a x86_64; do
  in="$SRC/app-$abi-release.apk"
  [ -f "$in" ] || { echo "missing $in"; exit 1; }
  out="$WORK/signed/linguapop-$VERSION-$abi.apk"
  # --alignment-preserved is load-bearing. Without it apksigner realigns the
  # archive, shifting every entry's offset by a few bytes. Entry *contents*
  # stay identical, so a content-level comparison looks clean — but the v2/v3
  # signature digests cover the whole file, so F-Droid's check of its own
  # build against this binary fails with a CHUNKED_SHA512 mismatch.
  "$APKSIGNER" sign \
    --alignment-preserved \
    --ks "$KP_storeFile" --ks-pass "pass:$KP_storePassword" \
    --ks-key-alias "$KP_keyAlias" --key-pass "pass:$KP_keyPassword" \
    --out "$out" "$in"
  # Every zip entry must survive signing untouched, or F-Droid's verification
  # of its own build against this binary can't succeed.
  python3 "$REPO_ROOT/tool/check_reproducible.py" --signing-only "$in" "$out"
  fp="$("$APKSIGNER" verify --print-certs "$out" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1)"
  echo "   $(basename "$out")  cert=$fp"
  ASSETS+=("$out")
done

echo
echo "== certificate fingerprint for AllowedAPKSigningKeys:"
"$APKSIGNER" verify --print-certs "${ASSETS[0]}" 2>/dev/null | sed -n 's/.*certificate SHA-256 digest: //p' | head -1

echo
echo "== uploading to release v$VERSION"
gh release upload "v$VERSION" "${ASSETS[@]}" --clobber
echo "done"
