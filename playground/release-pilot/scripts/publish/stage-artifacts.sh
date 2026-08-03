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
PACKAGING="jar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --jar) JAR_SOURCE="$2"; shift 2 ;;
    --pom) POM_SOURCE="$2"; shift 2 ;;
    --sbom) SBOM_SOURCE="$2"; shift 2 ;;
    --packaging) PACKAGING="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR --pom POM --sbom JSON [--jar JAR] [--packaging jar|pom]"
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR --pom POM --sbom JSON [--jar JAR] [--packaging jar|pom]" ;;
  esac
done

for req in MANIFEST STAGING POM_SOURCE SBOM_SOURCE; do
  if [[ -z "${!req}" ]]; then
    usage "$0 --manifest PATH --staging DIR --pom POM --sbom JSON [--jar JAR] [--packaging jar|pom]"
  fi
done

case "$PACKAGING" in
  jar)
    [[ -n "$JAR_SOURCE" && -f "$JAR_SOURCE" ]] || {
      echo "error: --jar is required for packaging=jar" >&2
      exit 1
    }
    ;;
  pom)
    ;;
  *)
    echo "error: unknown --packaging: $PACKAGING (expected jar|pom)" >&2
    exit 1
    ;;
esac

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
guidance_dest="$STAGING/${artifactId}-${version}-recipient-guidance.yaml"

if [[ "$PACKAGING" == "jar" ]]; then
  cp "$JAR_SOURCE" "$jar_dest"
fi
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

echo "staged $STAGING (packaging=$PACKAGING)"
ls -1 "$STAGING"
