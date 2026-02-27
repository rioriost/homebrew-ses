#!/usr/bin/env bash
set -euo pipefail

# Local release script for ses (full flow)
# Usage:
#   VERSION=0.0.1 ./scripts/release.sh
#   BUMP=minor ./scripts/release.sh
#   ./scripts/release.sh  (defaults to patch bump from latest tag)
#
# Outputs:
#   ses-<version>-macos.tar.gz, SHA256, GitHub Release, and Formula update
#
# Env:
#   RELEASE_REPO=rioriost/homebrew-ses (default)
#   ALLOW_DIRTY=1 (skip clean working tree enforcement)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_RELATIVE=".build/release/ses"
FORMULA_PATH="$ROOT_DIR/Formula/ses.rb"
RELEASE_REPO="${RELEASE_REPO:-rioriost/homebrew-ses}"

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
  if [[ -z "${ALLOW_DIRTY:-}" ]]; then
    if ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet; then
      echo "ERROR: working tree has uncommitted changes (set ALLOW_DIRTY=1 to override)" >&2
      exit 1
    fi
  fi
fi

echo "==> generating BuildVersion.swift"
VERSION="$VERSION_STR" bash "$ROOT_DIR/scripts/generate-version.sh"

if command -v git >/dev/null 2>&1; then
  if ! git -C "$ROOT_DIR" diff --quiet -- "Sources/ses/Core/BuildVersion.swift"; then
    echo "==> committing BuildVersion.swift"
    git -C "$ROOT_DIR" add "Sources/ses/Core/BuildVersion.swift"
    git -C "$ROOT_DIR" commit -m "build: set version ${VERSION_STR}"
  fi
fi

echo "==> building release binary"
swift build -c release --product ses

if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: missing binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> creating archive: $ARCHIVE"
tar -czf "$ROOT_DIR/$ARCHIVE" -C "$(dirname "$BIN_PATH")" "$(basename "$BIN_PATH")"

echo "==> sha256"
SHA="$(shasum -a 256 "$ROOT_DIR/$ARCHIVE" | awk '{print $1}')"
echo "$SHA  $ROOT_DIR/$ARCHIVE"

TAG="v${VERSION_STR}"

echo "==> creating tag ${TAG}"
git -C "$ROOT_DIR" tag -f "$TAG"

echo "==> pushing tag ${TAG}"
git -C "$ROOT_DIR" push origin "$TAG" --force

if command -v gh >/dev/null 2>&1; then
  if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "==> updating GitHub Release ${TAG} in ${RELEASE_REPO}"
    gh release upload "$TAG" "$ROOT_DIR/$ARCHIVE" --clobber --repo "$RELEASE_REPO"
  else
    echo "==> creating GitHub Release ${TAG} in ${RELEASE_REPO}"
    gh release create "$TAG" "$ROOT_DIR/$ARCHIVE" -t "$TAG" -n "Release ${TAG}" --repo "$RELEASE_REPO"
  fi
else
  echo "WARN: gh not installed; skipping GitHub Release creation" >&2
fi

if [[ -f "$FORMULA_PATH" ]]; then
  echo "==> updating Formula at $FORMULA_PATH"
  cat > "$FORMULA_PATH" <<EOF
class Ses < Formula
  desc "Speech Event Stream CLI"
  homepage "https://github.com/${RELEASE_REPO}"
  url "https://github.com/${RELEASE_REPO}/releases/download/${TAG}/ses-${VERSION_STR}-macos.tar.gz"
  sha256 "${SHA}"
  version "${VERSION_STR}"

  def install
    bin.install "ses"
  end
end
EOF

  echo "==> committing and pushing formula update"
  git -C "$ROOT_DIR" add "$FORMULA_PATH"
  git -C "$ROOT_DIR" commit -m "brew: bump ses formula to ${VERSION_STR}"
  git -C "$ROOT_DIR" push origin HEAD
else
  echo "WARN: Formula not found at $FORMULA_PATH; skipping formula update" >&2
fi

echo "==> done"
echo "Archive: $ROOT_DIR/$ARCHIVE"
echo "Release: https://github.com/${RELEASE_REPO}/releases/tag/${TAG}"
