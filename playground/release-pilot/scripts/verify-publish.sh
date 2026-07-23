#!/usr/bin/env bash
# Post-publish verification for SBOM, OpenVEX, signatures, and Nexus resolve.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
load_nexus_config

MANIFEST=""
STAGING=""
SKIP_NEXUS=false
SKIP_SIGNATURES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --skip-nexus) SKIP_NEXUS=true; shift ;;
    --skip-signatures) SKIP_SIGNATURES=true; shift ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR [--skip-nexus] [--skip-signatures]"
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR [--skip-nexus]" ;;
  esac
done

[[ -n "$MANIFEST" && -n "$STAGING" ]] || usage "$0 --manifest PATH --staging DIR [--skip-nexus] [--skip-signatures]"

if skip_sign_by_default; then
  SKIP_SIGNATURES=true
fi

require_cmd jq

groupId="$(manifest_field "$MANIFEST" '.coordinate.groupId')"
artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
prefix="$STAGING/${artifactId}-${version}"
expected_purl="$(purl_for_coordinate "$groupId" "$artifactId" "$version")"

echo "== signatures =="
if $SKIP_SIGNATURES; then
  echo "skip: OSERA_SKIP_SIGN enabled (playground test phase)"
elif command -v gpg >/dev/null 2>&1; then
  for file in "${prefix}.jar" "${prefix}.openvex.json"; do
    [[ -f "$file" ]] || continue
    [[ -f "${file}.asc" ]] && gpg --verify "${file}.asc" "$file"
    [[ -f "${file}.asc.finos" ]] && gpg --verify "${file}.asc.finos" "$file"
  done
else
  echo "skip: gpg not installed"
fi

echo "== SBOM =="
sbom="${prefix}-cyclonedx.json"
[[ -f "$sbom" ]] || { echo "error: missing $sbom" >&2; exit 1; }
if command -v cyclonedx >/dev/null 2>&1; then
  cyclonedx validate --input-file "$sbom" --input-format json --input-version v1_5
fi
bom_ref="$(jq -r '.metadata.component["bom-ref"] // empty' "$sbom")"
echo "bom-ref: ${bom_ref:-<none>} (expected $expected_purl)"

echo "== OpenVEX =="
openvex="${prefix}.openvex.json"
[[ -f "$openvex" ]] || { echo "error: missing $openvex" >&2; exit 1; }
jq '.statements[] | {cve: .vulnerability.name, status, product: .products[0]["@id"]}' "$openvex"

if ! $SKIP_NEXUS; then
  echo "== Nexus resolve =="
  require_cmd mvn
  mvn dependency:get \
    -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
    -Dartifact="${groupId}:${artifactId}:${version}" \
    -Dtransitive=false
fi

echo "verification passed"
