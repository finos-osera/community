#!/usr/bin/env bash
# FINOS co-signatures (.asc.finos) for vendor-signed staged files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

STAGING=""
ARTIFACT_ID=""
VERSION=""
PACKAGING="jar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staging) STAGING="$2"; shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --packaging) PACKAGING="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --staging DIR --artifact-id ID --version VERSION [--packaging jar|pom]"
      echo "requires: FINOS_GPG_KEY_ID, FINOS_GPG_PASSPHRASE"
      exit 0
      ;;
    *) usage "$0 --staging DIR --artifact-id ID --version VERSION [--packaging jar|pom]" ;;
  esac
done

[[ -n "$STAGING" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || \
  usage "$0 --staging DIR --artifact-id ID --version VERSION"
[[ -n "${FINOS_GPG_KEY_ID:-}" && -n "${FINOS_GPG_PASSPHRASE:-}" ]] || {
  echo "error: set FINOS_GPG_KEY_ID and FINOS_GPG_PASSPHRASE" >&2
  exit 1
}

require_cmd gpg

while IFS= read -r file; do
  [[ -f "${file}.asc" ]] || {
    echo "error: missing vendor signature for $file — run vendor-sign.sh first" >&2
    exit 1
  }
  gpg --batch --pinentry-mode loopback --passphrase "$FINOS_GPG_PASSPHRASE" \
    --armor --detach-sign \
    --local-user "$FINOS_GPG_KEY_ID" \
    --output "${file}.asc.finos" \
    "$file"
  gpg --verify "${file}.asc.finos" "$file"
  echo "finos co-signed $file"
done < <(existing_sign_targets "$STAGING" "$ARTIFACT_ID" "$VERSION" "$PACKAGING")
