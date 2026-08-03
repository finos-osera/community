#!/usr/bin/env bash
# Upload staged artifacts to Nexus via mvn deploy:deploy-file.
# OpenPGP sidecars (.asc / .asc.finos) are PUT next to each file (Maven Central
# layout). Classifier-based asc uploads are rejected by Nexus as invalid mavenPath.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"
load_nexus_config

MANIFEST=""
STAGING=""
DRY_RUN=false
PACKAGING="jar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --packaging) PACKAGING="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR [--packaging jar|pom] [--dry-run]"
      echo "env: NEXUS_URL, REPOSITORY_ID (defaults from config/nexus-playground.env)"
      echo "     NEXUS_USERNAME, NEXUS_PASSWORD (optional; else ~/.m2/settings.xml)"
      echo "When OSERA_SKIP_SIGN=0, requires .asc + .asc.finos and uploads them as siblings."
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR [--packaging jar|pom] [--dry-run]" ;;
  esac
done

[[ -n "$MANIFEST" && -n "$STAGING" ]] || usage "$0 --manifest PATH --staging DIR [--dry-run]"
require_cmd mvn

case "$PACKAGING" in
  jar|pom) ;;
  *) echo "error: unknown --packaging: $PACKAGING" >&2; exit 1 ;;
esac

groupId="$(manifest_field "$MANIFEST" '.coordinate.groupId')"
artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
prefix="$STAGING/${artifactId}-${version}"
pom_file="${prefix}.pom"
jar_file="${prefix}.jar"

require_signatures=true
if skip_sign_by_default; then
  require_signatures=false
fi

if $require_signatures; then
  while IFS= read -r file; do
    require_signature_sidecars "$file"
  done < <(existing_sign_targets "$STAGING" "$artifactId" "$version" "$PACKAGING")
fi

nexus_version_url() {
  nexus_gav_base_url "$groupId" "$artifactId" "$version"
}

# PUT a file into the GAV directory using the exact basename (e.g. foo.jar.asc).
put_nexus_file() {
  local local_file="$1"
  local remote_name="$2"
  local url
  url="$(nexus_version_url)/${remote_name}"

  if $DRY_RUN; then
    echo "dry-run: PUT $url ← $local_file"
    return 0
  fi

  require_cmd curl
  echo "uploading signature sidecar: $remote_name"
  curl -sS -L --fail-with-body \
    --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
    -H "Content-Type: application/octet-stream" \
    --upload-file "$local_file" \
    "$url"
  echo
}

put_signature_sidecars() {
  local file="$1"
  local base
  base="$(basename "$file")"

  if [[ -f "${file}.asc" ]]; then
    put_nexus_file "${file}.asc" "${base}.asc"
  elif $require_signatures; then
    echo "error: missing vendor signature: ${file}.asc" >&2
    exit 1
  fi

  if [[ -f "${file}.asc.finos" ]]; then
    put_nexus_file "${file}.asc.finos" "${base}.asc.finos"
  elif $require_signatures; then
    echo "error: missing FINOS co-signature: ${file}.asc.finos" >&2
    exit 1
  fi
}

# Sidecar / attachment deploy — never generate or redeploy a POM (avoids Nexus 409).
deploy_attachment() {
  local file="$1" packaging="$2" classifier="${3:-}"
  local -a extra=(-DgeneratePom=false)
  if [[ -n "$classifier" ]]; then
    extra+=(-Dclassifier="$classifier")
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
deploy_primary_jar() {
  local -a extra=(-DpomFile="$pom_file" -DgeneratePom=false)

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

# POM-only (e.g. spring-framework-bom).
deploy_primary_pom() {
  if $DRY_RUN; then
    echo "dry-run: mvn deploy:deploy-file -Dfile=$pom_file -DpomFile=$pom_file -Dpackaging=pom -DgeneratePom=false"
    return 0
  fi

  mvn deploy:deploy-file \
    -Durl="$NEXUS_URL" \
    -DrepositoryId="$REPOSITORY_ID" \
    -DgroupId="$groupId" \
    -DartifactId="$artifactId" \
    -Dversion="$version" \
    -Dpackaging=pom \
    -Dfile="$pom_file" \
    -DpomFile="$pom_file" \
    -DgeneratePom=false
}

[[ -f "$pom_file" ]] || { echo "error: missing $pom_file" >&2; exit 1; }
if [[ "$PACKAGING" == "jar" ]]; then
  [[ -f "$jar_file" ]] || { echo "error: missing $jar_file" >&2; exit 1; }
fi

if $require_signatures || [[ -f "${jar_file}.asc" ]] || [[ -f "${pom_file}.asc" ]]; then
  load_nexus_credentials
fi

if [[ "$PACKAGING" == "jar" ]]; then
  deploy_primary_jar
  put_signature_sidecars "$jar_file"
else
  deploy_primary_pom
fi
put_signature_sidecars "$pom_file"

deploy_attachment "${prefix}-cyclonedx.json" json cyclonedx
put_signature_sidecars "${prefix}-cyclonedx.json"

deploy_attachment "${prefix}.openvex.json" json openvex
put_signature_sidecars "${prefix}.openvex.json"

if [[ -f "${prefix}-recipient-guidance.yaml" ]]; then
  deploy_attachment "${prefix}-recipient-guidance.yaml" yaml recipient-guidance
  put_signature_sidecars "${prefix}-recipient-guidance.yaml"
fi

echo "publish complete for ${groupId}:${artifactId}:${version} (packaging=${PACKAGING})"
echo "nexus: ${NEXUS_URL}"
