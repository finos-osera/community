#!/usr/bin/env bash
# Generate OpenVEX JSON and recipient-guidance.yaml from a release manifest.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

MANIFEST=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --manifest PATH [--output-dir DIR]"
      exit 0
      ;;
    *) usage "$0 --manifest PATH [--output-dir DIR]" ;;
  esac
done

[[ -n "$MANIFEST" && -f "$MANIFEST" ]] || usage "$0 --manifest PATH [--output-dir DIR]"

require_cmd jq

OUTPUT_DIR="${OUTPUT_DIR:-$(dirname "$MANIFEST")}"
mkdir -p "$OUTPUT_DIR"

json="$(manifest_to_json "$MANIFEST")"
groupId="$(printf '%s' "$json" | jq -r '.coordinate.groupId')"
artifactId="$(printf '%s' "$json" | jq -r '.coordinate.artifactId')"
version="$(printf '%s' "$json" | jq -r '.coordinate.version')"
baselineTag="$(printf '%s' "$json" | jq -r '.baselineTag // empty')"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
purl="$(purl_for_coordinate "$groupId" "$artifactId" "$version")"
vex_id="https://osera.finos.org/vex/${groupId}/${artifactId}/${version}"

statements="$(printf '%s' "$json" | jq -c '
  [.vulnerabilities[]? | {
    vulnerability: { name: .id },
    products: [{ "@id": $purl }],
    status: (.status // "fixed"),
    action_statement: (.action // "Backpatch applied per OSERA release manifest.")
  }]
' --arg purl "$purl")"

openvex_path="$OUTPUT_DIR/${version}.openvex.json"
guidance_path="$OUTPUT_DIR/${version}.recipient-guidance.yaml"

jq -n \
  --arg context "https://openvex.dev/ns/v0.2.0" \
  --arg id "$vex_id" \
  --arg author "OSERA Patch Provider" \
  --arg timestamp "$timestamp" \
  --argjson statements "$statements" \
  '{
    "@context": $context,
    "@id": $id,
    author: $author,
    timestamp: $timestamp,
    version: 1,
    statements: $statements
  }' > "$openvex_path"

{
  echo "coordinate:"
  echo "  groupId: $groupId"
  echo "  artifactId: $artifactId"
  echo "  version: $version"
  echo "patchBasis: $(printf '%s' "$json" | jq -r '.patchBasis // "upstream-backport"')"
  echo "whatChanged:"
  printf '%s' "$json" | jq -r '.recipientGuidance.whatChanged[]? // empty' | sed 's/^/  - /'
  echo "suggestedTestSurface:"
  printf '%s' "$json" | jq -r '.recipientGuidance.suggestedTestSurface[]? // empty' | sed 's/^/  - /'
} > "$guidance_path"

echo "wrote $openvex_path"
echo "wrote $guidance_path"
