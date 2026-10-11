#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
key_dir="${TIKETIX_SCANNER_SIGNING_DIR:-$HOME/.local/share/tiketix/scanner-signing}"
export TIKETIX_SCANNER_KEYSTORE="$key_dir/release.p12"
export TIKETIX_SCANNER_STORE_PASSWORD="$(<"$key_dir/password.txt")"
export TIKETIX_SCANNER_KEY_PASSWORD="$TIKETIX_SCANNER_STORE_PASSWORD"
export TIKETIX_SCANNER_KEY_ALIAS="tiketix-scanner"
cd "$root"
version="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
flutter build apk --release --obfuscate --split-debug-info=build/private-symbols \
  --dart-define="API_URL=${API_URL:-https://tiketix.co.tz}" \
  --dart-define="APP_VERSION=$version"
sha256sum build/app/outputs/flutter-apk/app-release.apk
