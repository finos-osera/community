#!/usr/bin/env bash
# Vendor detached GPG signatures (.asc) for staged release files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

STAGING=""
ARTIFACT_ID=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging) STAGING="$2"; shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --staging DIR --artifact-id ID --version VERSION"
      echo "requires: VENDOR_GPG_KEY_ID"
      exit 0
      ;;
    *) usage "$0 --staging DIR --artifact-id ID --version VERSION" ;;
  esac
done

[[ -n "$STAGING" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || \
  usage "$0 --staging DIR --artifact-id ID --version VERSION"
[[ -n "${VENDOR_GPG_KEY_ID:-}" ]] || {
  echo "error: set VENDOR_GPG_KEY_ID" >&2
  exit 1
}

require_cmd gpg

prefix="$STAGING/${ARTIFACT_ID}-${VERSION}"
files=(
  "${prefix}.jar"
  "${prefix}.pom"
  "${prefix}-cyclonedx.json"
  "${prefix}.openvex.json"
  "${prefix}-recipient-guidance.yaml"
)

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue
  gpg --batch --yes --armor --detach-sign \
    --local-user "$VENDOR_GPG_KEY_ID" \
    --output "${file}.asc" \
    "$file"
  gpg --verify "${file}.asc" "$file"
  echo "vendor-signed $file"
done
