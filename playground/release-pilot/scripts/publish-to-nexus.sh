#!/usr/bin/env bash
# Upload staged artifacts to Nexus via mvn deploy:deploy-file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
load_nexus_config

MANIFEST=""
STAGING=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR [--dry-run]"
      echo "env: NEXUS_URL, REPOSITORY_ID (defaults from config/nexus-playground.env)"
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR [--dry-run]" ;;
  esac
done

[[ -n "$MANIFEST" && -n "$STAGING" ]] || usage "$0 --manifest PATH --staging DIR [--dry-run]"
require_cmd mvn

groupId="$(manifest_field "$MANIFEST" '.coordinate.groupId')"
artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
prefix="$STAGING/${artifactId}-${version}"
pom_file="${prefix}.pom"
jar_file="${prefix}.jar"

# Sidecar / attachment deploy — never generate or redeploy a POM (avoids Nexus 409).
deploy_attachment() {
  local file="$1" packaging="$2" classifier="${3:-}"
  local -a extra=(-DgeneratePom=false)
  if [[ -n "$classifier" ]]; then
    extra+=(-Dclassifier="$classifier")
  fi
  if [[ -f "${file}.asc" && -f "${file}.asc.finos" ]]; then
    extra+=(-Dfiles="${file}.asc,${file}.asc.finos" -Dtypes=asc,asc -Dclassifiers=vendor,finos)
  fi

  if $DRY_RUN; then
    echo "dry-run: mvn deploy:deploy-file -Dfile=$file -Dpackaging=$packaging -DgeneratePom=false ${extra[*]:-}"
    return 0
  fi

  mvn deploy:deploy-file \
    -Durl="$NEXUS_URL" \
    -DrepositoryId="$REPOSITORY_ID" \
    -DgroupId="$groupId" \
    -DartifactId="$artifactId" \
    -Dversion="$version" \
    -Dpackaging="$packaging" \
    -Dfile="$file" \
    "${extra[@]}"
}

# Primary JAR + POM in a single deploy (never deploy pom twice).
deploy_primary() {
  local -a extra=(-DpomFile="$pom_file" -DgeneratePom=false)
  if [[ -f "${jar_file}.asc" && -f "${jar_file}.asc.finos" ]]; then
    extra+=(-Dfiles="${jar_file}.asc,${jar_file}.asc.finos" -Dtypes=asc,asc -Dclassifiers=vendor,finos)
  fi

  if $DRY_RUN; then
    echo "dry-run: mvn deploy:deploy-file -Dfile=$jar_file -DpomFile=$pom_file -Dpackaging=jar -DgeneratePom=false"
    return 0
  fi

  mvn deploy:deploy-file \
    -Durl="$NEXUS_URL" \
    -DrepositoryId="$REPOSITORY_ID" \
    -DgroupId="$groupId" \
    -DartifactId="$artifactId" \
    -Dversion="$version" \
    -Dpackaging=jar \
    -Dfile="$jar_file" \
    "${extra[@]}"
}

[[ -f "$jar_file" ]] || { echo "error: missing $jar_file" >&2; exit 1; }
[[ -f "$pom_file" ]] || { echo "error: missing $pom_file" >&2; exit 1; }

deploy_primary
deploy_attachment "${prefix}-cyclonedx.json" json cyclonedx
deploy_attachment "${prefix}.openvex.json" json openvex
[[ -f "${prefix}-recipient-guidance.yaml" ]] && \
  deploy_attachment "${prefix}-recipient-guidance.yaml" yaml recipient-guidance

for ext in asc asc.finos; do
  [[ -f "${prefix}-cyclonedx.json.${ext}" ]] && \
    deploy_attachment "${prefix}-cyclonedx.json.${ext}" "$ext" cyclonedx
  [[ -f "${prefix}.openvex.json.${ext}" ]] && \
    deploy_attachment "${prefix}.openvex.json.${ext}" "$ext" openvex
done

echo "publish complete for ${groupId}:${artifactId}:${version}"
echo "nexus: ${NEXUS_URL}"
