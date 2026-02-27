#!/usr/bin/env bash
set -euo pipefail

# Generate BuildVersion.swift from a resolved version string.
# Priority:
# 1) VERSION env var (explicit override)
# 2) git describe --tags (if available)
# 3) fallback "0.0.0"

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    echo "${VERSION#v}"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    if git describe --tags --abbrev=0 >/dev/null 2>&1; then
      echo "$(git describe --tags --abbrev=0)" | sed 's/^v//'
      return 0
    fi
  fi

  echo "0.0.0"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="$ROOT_DIR/Sources/ses/Core/BuildVersion.swift"
VERSION_STR="$(resolve_version)"

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
import Foundation

public enum BuildVersion {
    public static let value = "$VERSION_STR"
}
EOF
