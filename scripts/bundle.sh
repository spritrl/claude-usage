#!/usr/bin/env bash
# Construit ClaudeUsage en release et l'emballe dans build/ClaudeUsage.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/ClaudeUsage"
APP="build/ClaudeUsage.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Ressources SwiftPM (traductions) : Bundle.module les cherche dans Contents/Resources.
cp -R "$(dirname "$BIN")/ClaudeUsage_ClaudeUsage.bundle" "$APP/Contents/Resources/"
# Dossiers lproj vides pour que macOS liste l'app dans Réglages > Langue et région.
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/fr.lproj"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signature ad hoc par défaut ; CODESIGN_IDENTITY="Apple Development: ..." pour une vraie identité.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "→ $APP"
