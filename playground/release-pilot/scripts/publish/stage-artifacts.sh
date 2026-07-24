#!/usr/bin/env bash
# Copy build outputs and sidecars into an operator staging directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

MANIFEST=""
STAGING=""
JAR_SOURCE=""
POM_SOURCE=""
SBOM_SOURCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --jar) JAR_SOURCE="$2"; shift 2 ;;
    --pom) POM_SOURCE="$2"; shift 2 ;;
    --sbom) SBOM_SOURCE="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR --jar JAR --pom POM --sbom JSON"
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR --jar JAR --pom POM --sbom JSON" ;;
  esac
done

for req in MANIFEST STAGING JAR_SOURCE POM_SOURCE SBOM_SOURCE; do
  if [[ -z "${!req}" ]]; then
    usage "$0 --manifest PATH --staging DIR --jar JAR --pom POM --sbom JSON"
  fi
done

require_cmd jq

artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
release_dir="$(dirname "$MANIFEST")"

mkdir -p "$STAGING"

jar_dest="$STAGING/${artifactId}-${version}.jar"
pom_dest="$STAGING/${artifactId}-${version}.pom"
sbom_dest="$STAGING/${artifactId}-${version}-cyclonedx.json"
openvex_src="$release_dir/${version}.openvex.json"
openvex_dest="$STAGING/${artifactId}-${version}.openvex.json"
guidance_src="$release_dir/${version}.recipient-guidance.yaml"
guidance_dest="$STAGING/${artifactId}-${version}.recipient-guidance.yaml"

cp "$JAR_SOURCE" "$jar_dest"
cp "$POM_SOURCE" "$pom_dest"
cp "$SBOM_SOURCE" "$sbom_dest"

[[ -f "$openvex_src" ]] || {
  echo "error: missing OpenVEX — run scripts/release/generate-openvex.sh first" >&2
  exit 1
}
cp "$openvex_src" "$openvex_dest"

if [[ -f "$guidance_src" ]]; then
  cp "$guidance_src" "$guidance_dest"
fi

echo "staged $STAGING"
ls -1 "$STAGING"
