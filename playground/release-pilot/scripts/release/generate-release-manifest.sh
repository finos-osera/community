#!/usr/bin/env bash
# Generate release manifest YAML from git tags/commits (baseline..publish).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$ROOT/scripts"
# shellcheck source=../lib/common.sh
source "$SCRIPTS/lib/common.sh"
# shellcheck source=../lib/generate_release_manifest.sh
source "$SCRIPTS/lib/generate_release_manifest.sh"

REPO_DIR=""
TAG=""
GROUP_ID=""
ARTIFACT_ID=""
BASELINE_TAG=""
GITHUB_ORG=""
OUTPUT=""
WITH_SIDECARS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --baseline-tag) BASELINE_TAG="$2"; shift 2 ;;
    --github-org) GITHUB_ORG="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --with-sidecars) WITH_SIDECARS=true; shift ;;
    -h|--help)
      cat <<EOF >&2
usage: $0 --repo-dir PATH --tag TAG --group-id G --artifact-id A [options]

Generate {version}.yaml from commits between baseline and publish tags.

Options:
  --baseline-tag TAG   default: v{upstream}+backpatch.baseline derived from --tag
  --github-org ORG     default: parsed from origin remote
  --output PATH        default: /tmp/osera-releases/{repo}/{version}.yaml
  --with-sidecars      also run generate-openvex.sh on the manifest

Example (h2):
  $0 --repo-dir /tmp/backpatch-h2-build \\
     --tag v1.4.200+backpatch.001 \\
     --group-id com.h2database --artifact-id h2 \\
     --with-sidecars
EOF
      exit 0
      ;;
    *) echo "usage: $0 --help" >&2; exit 1 ;;
  esac
done

[[ -n "$REPO_DIR" && -n "$TAG" && -n "$GROUP_ID" && -n "$ARTIFACT_ID" ]] || {
  echo "error: --repo-dir, --tag, --group-id, --artifact-id are required" >&2
  exit 1
}

require_cmd git
require_cmd jq

manifest_path="$(generate_release_manifest \
  "$REPO_DIR" "$TAG" "$GROUP_ID" "$ARTIFACT_ID" \
  "$BASELINE_TAG" "$GITHUB_ORG" "$OUTPUT")"
echo "wrote $manifest_path" >&2

if $WITH_SIDECARS; then
  "$SCRIPTS/release/generate-openvex.sh" --manifest "$manifest_path"
fi

echo "$manifest_path"
