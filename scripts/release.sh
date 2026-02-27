#!/usr/bin/env bash
set -euo pipefail

# Local release script for ses
# Usage:
#   VERSION=0.0.1 ./scripts/release.sh
#   BUMP=minor ./scripts/release.sh
#   ./scripts/release.sh  (defaults to patch bump from latest tag)
#
# Outputs:
#   ses-<version>-macos.tar.gz and SHA256

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_RELATIVE=".build/release/ses"

bump_version() {
  local base="$1"
  local bump="${2:-patch}"
  IFS='.' read -r major minor patch <<< "$base"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch|*)
      patch=$((patch + 1))
      ;;
  esac

  echo "${major}.${minor}.${patch}"
}

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    echo "${VERSION#v}"
    return 0
  fi

  local base="0.0.0"
  if command -v git >/dev/null 2>&1; then
    if git -C "$ROOT_DIR" describe --tags --abbrev=0 >/dev/null 2>&1; then
      base="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 | sed 's/^v//')"
    fi
  fi

  bump_version "$base" "${BUMP:-patch}"
}

VERSION_STR="$(resolve_version)"
ARCHIVE="ses-${VERSION_STR}-macos.tar.gz"
BIN_PATH="$ROOT_DIR/$BIN_RELATIVE"

echo "==> version: ${VERSION_STR}"
echo "==> root: ${ROOT_DIR}"

if command -v git >/dev/null 2>&1; then
  if ! git -C "$ROOT_DIR" diff --quiet; then
    echo "WARN: working tree has uncommitted changes" >&2
  fi
fi

echo "==> generating BuildVersion.swift"
VERSION="$VERSION_STR" bash "$ROOT_DIR/scripts/generate-version.sh"

echo "==> building release binary"
swift build -c release --product ses

if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: missing binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> creating archive: $ARCHIVE"
tar -czf "$ROOT_DIR/$ARCHIVE" -C "$(dirname "$BIN_PATH")" "$(basename "$BIN_PATH")"

echo "==> sha256"
shasum -a 256 "$ROOT_DIR/$ARCHIVE"

echo "==> done"
echo "Archive: $ROOT_DIR/$ARCHIVE"
echo "Next: upload to GitHub Release v${VERSION_STR}"
