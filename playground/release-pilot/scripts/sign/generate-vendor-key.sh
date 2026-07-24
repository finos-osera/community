#!/usr/bin/env bash
# Generate a playground vendor (producer) OpenPGP key and certify it with FINOS.
# Requires FINOS key from generate-finos-key.sh (source signing/local.env first).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

VENDOR_SLUG=""
VENDOR_NAME=""
VENDOR_EMAIL=""
PASSPHRASE="${VENDOR_GPG_PASSPHRASE:-osera-playground-vendor}"
SIGNING_DIR="${SIGNING_DIR:-$ROOT/signing}"
GNUPGHOME="${GNUPGHOME:-$SIGNING_DIR/gnupg}"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor-slug) VENDOR_SLUG="$2"; shift 2 ;;
    --name) VENDOR_NAME="$2"; shift 2 ;;
    --email) VENDOR_EMAIL="$2"; shift 2 ;;
    --passphrase) PASSPHRASE="$2"; shift 2 ;;
    --signing-dir) SIGNING_DIR="$2"; GNUPGHOME="$SIGNING_DIR/gnupg"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help)
      cat <<EOF
usage: $0 --vendor-slug SLUG [--name NAME] [--email EMAIL] [--passphrase PASS]
          [--signing-dir DIR] [--force]

Creates a vendor OpenPGP key and has FINOS certify the uid (local trust chain).
Requires: FINOS_GPG_KEY_ID, FINOS_GPG_PASSPHRASE (source signing/local.env).
Exports:
  signing/vendors/{slug}.asc
  appends VENDOR_GPG_KEY_ID to signing/local.env
EOF
      exit 0
      ;;
    *) usage "$0 --vendor-slug SLUG ..." ;;
  esac
done

[[ -n "$VENDOR_SLUG" ]] || usage "$0 --vendor-slug SLUG ..."
VENDOR_NAME="${VENDOR_NAME:-OSERA Vendor ${VENDOR_SLUG}}"
VENDOR_EMAIL="${VENDOR_EMAIL:-osera-vendor-${VENDOR_SLUG}@example.com}"

[[ -n "${FINOS_GPG_KEY_ID:-}" && -n "${FINOS_GPG_PASSPHRASE:-}" ]] || {
  echo "error: set FINOS_GPG_KEY_ID and FINOS_GPG_PASSPHRASE (source signing/local.env)" >&2
  exit 1
}

require_cmd gpg
export GNUPGHOME
mkdir -p "$GNUPGHOME" "$SIGNING_DIR/vendors"
chmod 700 "$GNUPGHOME"

pub_out="$SIGNING_DIR/vendors/${VENDOR_SLUG}.asc"
env_out="$SIGNING_DIR/local.env"

if [[ -f "$pub_out" && "$FORCE" != true ]]; then
  echo "error: $pub_out already exists (pass --force to recreate)" >&2
  exit 1
fi

if [[ "$FORCE" == true ]]; then
  # Remove prior keys for this vendor email so regeneration is deterministic.
  while IFS= read -r old_fpr; do
    [[ -n "$old_fpr" ]] || continue
    gpg --batch --yes --delete-secret-and-public-key "$old_fpr" || true
  done < <(gpg --list-secret-keys --with-colons "$VENDOR_EMAIL" 2>/dev/null | awk -F: '/^fpr:/ { print $10 }')
  rm -f "$pub_out"
fi

batch="$(mktemp "${TMPDIR:-/tmp}/osera-vendor-key.XXXXXX")"
trap 'rm -f "$batch"' EXIT
cat > "$batch" <<EOF
%echo Generating vendor playground signing key
Key-Type: RSA
Key-Length: 3072
Key-Usage: sign
Name-Real: $VENDOR_NAME
Name-Email: $VENDOR_EMAIL
Expire-Date: 1y
Passphrase: $PASSPHRASE
%commit
%echo done
EOF

gpg --batch --generate-key "$batch"
# Prefer the newest secret key for this email (last sec/fpr pair).
vendor_key_id="$(gpg --list-secret-keys --with-colons "$VENDOR_EMAIL" | awk -F: '/^sec:/ { id=$5 } END { print id }')"
vendor_key_fpr="$(gpg --list-secret-keys --with-colons "$VENDOR_EMAIL" | awk -F: '/^fpr:/ { fpr=$10 } END { print fpr }')"
[[ -n "$vendor_key_id" && -n "$vendor_key_fpr" ]] || {
  echo "error: failed to resolve vendor key id for $VENDOR_EMAIL" >&2
  exit 1
}

# FINOS certifies the vendor uid (local analogue of "vendor approved by FINOS").
finos_fpr="${FINOS_GPG_KEY_FPR:-$FINOS_GPG_KEY_ID}"
gpg --batch --yes --pinentry-mode loopback --passphrase "$FINOS_GPG_PASSPHRASE" \
  --default-key "$finos_fpr" \
  --quick-sign-key "$vendor_key_fpr" "$VENDOR_NAME <$VENDOR_EMAIL>"
if ! gpg --list-sigs --with-colons "$vendor_key_fpr" | grep -q "^sig:.*:${finos_fpr}:"; then
  # Fall back to matching by short key id in sig packets.
  if ! gpg --list-sigs --with-colons "$vendor_key_fpr" | grep -q "^sig:.*:${FINOS_GPG_KEY_ID}:"; then
    echo "error: FINOS certification of vendor key failed" >&2
    exit 1
  fi
fi

gpg --armor --export "$vendor_key_fpr" > "$pub_out"

touch "$env_out"
chmod 600 "$env_out"
# Refresh vendor exports in local.env
tmp_env="$(mktemp "${TMPDIR:-/tmp}/osera-local-env.XXXXXX")"
grep -v -E '^export VENDOR_GPG_(KEY_ID|PASSPHRASE)=' "$env_out" > "$tmp_env" || true
{
  cat "$tmp_env"
  echo "export VENDOR_GPG_KEY_ID=$vendor_key_id"
  echo "export VENDOR_GPG_KEY_FPR=$vendor_key_fpr"
  echo "export VENDOR_GPG_PASSPHRASE=$(printf '%q' "$PASSPHRASE")"
  echo "export VENDOR_SLUG=$(printf '%q' "$VENDOR_SLUG")"
} > "$env_out"
rm -f "$tmp_env"
chmod 600 "$env_out"

echo "wrote $pub_out"
echo "updated $env_out"
echo "VENDOR_GPG_KEY_ID=$vendor_key_id"
echo "VENDOR_GPG_KEY_FPR=$vendor_key_fpr"
echo "FINOS certified vendor key $vendor_key_fpr"
