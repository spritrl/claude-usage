#!/usr/bin/env bash
# Met à jour Casks/claude-usage.rb dans le tap Homebrew (spritrl/homebrew-tap) pour une version donnée.
# Usage : scripts/update-cask.sh <version> <chemin/vers/ClaudeUsage.app.zip> [dossier du tap déjà cloné]
set -euo pipefail

VERSION="${1:?version (ex. 1.0.0)}"
ZIP="${2:?chemin vers ClaudeUsage.app.zip}"
TAP_DIR="${3:-}"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

if [ -z "$TAP_DIR" ]; then
  TAP_DIR="$(mktemp -d)/homebrew-tap"
  git clone --depth 1 "https://github.com/spritrl/homebrew-tap.git" "$TAP_DIR"
fi

CASK="$TAP_DIR/Casks/claude-usage.rb"
sed -i.bak -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$CASK"
rm -f "$CASK.bak"

cd "$TAP_DIR"
if git diff --quiet; then
  echo "Cask déjà à jour ($VERSION, $SHA)"
  exit 0
fi
git add Casks/claude-usage.rb
git -c user.name="${GIT_AUTHOR_NAME:-spritrl}" -c user.email="${GIT_AUTHOR_EMAIL:-pro.chrisrln@gmail.com}" \
  commit -m "claude-usage $VERSION"
git push origin HEAD:main
echo "→ cask claude-usage mis à jour : $VERSION ($SHA)"
