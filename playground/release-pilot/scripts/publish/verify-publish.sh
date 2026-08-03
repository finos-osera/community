#!/usr/bin/env bash
# Post-publish verification for SBOM, OpenVEX, signatures, and Nexus resolve.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"
load_nexus_config

MANIFEST=""
STAGING=""
SKIP_NEXUS=false
SKIP_SIGNATURES=""
PACKAGING="jar"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --packaging) PACKAGING="$2"; shift 2 ;;
    --skip-nexus) SKIP_NEXUS=true; shift ;;
    --skip-signatures) SKIP_SIGNATURES=true; shift ;;
    -h|--help)
      echo "usage: $0 --manifest PATH --staging DIR [--packaging jar|pom] [--skip-nexus] [--skip-signatures]"
      echo "When OSERA_SKIP_SIGN=0, requires + verifies vendor .asc and FINOS .asc.finos."
      echo "Without --skip-nexus, also checks JAR/POM/CycloneDX/OpenVEX (and sigs) exist on Nexus."
      exit 0
      ;;
    *) usage "$0 --manifest PATH --staging DIR [--packaging jar|pom] [--skip-nexus] [--skip-signatures]" ;;
  esac
done

[[ -n "$MANIFEST" && -n "$STAGING" ]] || usage "$0 --manifest PATH --staging DIR [--skip-nexus] [--skip-signatures]"

case "$PACKAGING" in
  jar|pom) ;;
  *) echo "error: unknown --packaging: $PACKAGING" >&2; exit 1 ;;
esac

if [[ -z "$SKIP_SIGNATURES" ]]; then
  if skip_sign_by_default; then
    SKIP_SIGNATURES=true
  else
    SKIP_SIGNATURES=false
  fi
fi

require_cmd jq

groupId="$(manifest_field "$MANIFEST" '.coordinate.groupId')"
artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
prefix="$STAGING/${artifactId}-${version}"
expected_purl="$(purl_for_coordinate "$groupId" "$artifactId" "$version")"

echo "== signatures (staging) =="
if $SKIP_SIGNATURES; then
  echo "skip: OSERA_SKIP_SIGN enabled (or --skip-signatures)"
else
  require_cmd gpg
  while IFS= read -r file; do
    require_signature_sidecars "$file"
    gpg --verify "${file}.asc" "$file"
    gpg --verify "${file}.asc.finos" "$file"
    echo "ok $file"
  done < <(existing_sign_targets "$STAGING" "$artifactId" "$version" "$PACKAGING")
fi

echo "== SBOM (staging) =="
sbom="${prefix}-cyclonedx.json"
[[ -f "$sbom" ]] || { echo "error: missing $sbom" >&2; exit 1; }
if command -v cyclonedx >/dev/null 2>&1; then
  cyclonedx validate --input-file "$sbom" --input-format json --input-version v1_5 || true
fi
bom_ref="$(jq -r '.metadata.component["bom-ref"] // empty' "$sbom")"
echo "bom-ref: ${bom_ref:-<none>} (expected $expected_purl)"

echo "== OpenVEX (staging) =="
openvex="${prefix}.openvex.json"
[[ -f "$openvex" ]] || { echo "error: missing $openvex" >&2; exit 1; }
jq '.statements[] | {cve: .vulnerability.name, status, product: .products[0]["@id"]}' "$openvex"

if ! $SKIP_NEXUS; then
  echo "== Nexus assets =="
  require_cmd mvn
  # Classified FEED-001 sidecars (must exist; unsigned publish still requires these).
  mvn dependency:get \
    -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
    -Dartifact="${groupId}:${artifactId}:${version}:json:cyclonedx" \
    -Dtransitive=false
  echo "ok nexus cyclonedx"
  mvn dependency:get \
    -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
    -Dartifact="${groupId}:${artifactId}:${version}:json:openvex" \
    -Dtransitive=false
  echo "ok nexus openvex"
  if [[ -f "${prefix}-recipient-guidance.yaml" ]]; then
    mvn dependency:get \
      -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
      -Dartifact="${groupId}:${artifactId}:${version}:yaml:recipient-guidance" \
      -Dtransitive=false
    echo "ok nexus recipient-guidance"
  fi

  if ! $SKIP_SIGNATURES; then
    require_cmd curl
    load_nexus_credentials
    base="$(nexus_gav_base_url "$groupId" "$artifactId" "$version")"
    require_nexus_asset() {
      local remote_name="$1"
      local code
      code="$(curl -sS -o /dev/null -w '%{http_code}' -L \
        --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
        -I "${base}/${remote_name}" || true)"
      if [[ "$code" != "200" ]]; then
        echo "error: Nexus missing ${remote_name} (HTTP ${code})" >&2
        echo "  url: ${base}/${remote_name}" >&2
        return 1
      fi
      echo "ok nexus $remote_name"
    }
    if [[ "$PACKAGING" == "jar" ]]; then
      require_nexus_asset "${artifactId}-${version}.jar.asc"
      require_nexus_asset "${artifactId}-${version}.jar.asc.finos"
    fi
    require_nexus_asset "${artifactId}-${version}.pom.asc"
    require_nexus_asset "${artifactId}-${version}.pom.asc.finos"
    require_nexus_asset "${artifactId}-${version}-cyclonedx.json.asc"
    require_nexus_asset "${artifactId}-${version}-cyclonedx.json.asc.finos"
    require_nexus_asset "${artifactId}-${version}.openvex.json.asc"
    require_nexus_asset "${artifactId}-${version}.openvex.json.asc.finos"
  fi

  echo "== Nexus resolve =="
  if [[ "$PACKAGING" == "pom" ]]; then
    mvn dependency:get \
      -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
      -Dartifact="${groupId}:${artifactId}:${version}:pom" \
      -Dtransitive=false
  else
    mvn dependency:get \
      -DremoteRepositories="${REPOSITORY_ID}::::${NEXUS_URL}" \
      -Dartifact="${groupId}:${artifactId}:${version}" \
      -Dtransitive=false
  fi
fi

echo "verification passed"
