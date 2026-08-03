#!/usr/bin/env bash
# Vendor detached GPG signatures (.asc) for staged release files.
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
      echo "requires: VENDOR_GPG_KEY_ID"
      exit 0
      ;;
    *) usage "$0 --staging DIR --artifact-id ID --version VERSION [--packaging jar|pom]" ;;
  esac
done

[[ -n "$STAGING" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || \
  usage "$0 --staging DIR --artifact-id ID --version VERSION"
[[ -n "${VENDOR_GPG_KEY_ID:-}" ]] || {
  echo "error: set VENDOR_GPG_KEY_ID" >&2
  exit 1
}

require_cmd gpg

gpg_sign_args=(--batch --yes --armor --detach-sign --local-user "$VENDOR_GPG_KEY_ID")
if [[ -n "${VENDOR_GPG_PASSPHRASE:-}" ]]; then
  gpg_sign_args+=(--pinentry-mode loopback --passphrase "$VENDOR_GPG_PASSPHRASE")
fi

while IFS= read -r file; do
  gpg "${gpg_sign_args[@]}" --output "${file}.asc" "$file"
  gpg --verify "${file}.asc" "$file"
  echo "vendor-signed $file"
done < <(existing_sign_targets "$STAGING" "$ARTIFACT_ID" "$VERSION" "$PACKAGING")
