#!/usr/bin/env bash
# Generate CycloneDX SBOM without editing backpatch repo build files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

MODE="maven"
MODULE_DIR="."
OUTPUT_FILE=""
JAR_FILE=""
GROUP_ID=""
ARTIFACT_ID=""
VERSION=""
REPO_DIR=""
GRADLE_INIT="${GRADLE_INIT:-$ROOT/templates/cyclonedx-gradle.init.gradle}"
SPRING_JDK_COMPAT_INIT="${SPRING_JDK_COMPAT_INIT:-$ROOT/templates/spring-jdk-compat.init.gradle}"
CYCLONEDX_PLUGIN_VERSION="${CYCLONEDX_PLUGIN_VERSION:-2.9.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --module-dir) MODULE_DIR="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --jar) JAR_FILE="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --aggregate) MODE="maven-aggregate"; shift ;;
    -h|--help)
      echo "usage: $0 --output FILE [--mode maven|maven-aggregate|gradle|cli|coordinate]"
      echo "  maven*: --module-dir DIR"
      echo "  gradle: --repo-dir DIR --module-dir DIR [--version V]"
      echo "  cli: --jar FILE"
      echo "  coordinate: --group-id G --artifact-id A --version V  (minimal component SBOM)"
      exit 0
      ;;
    *) usage "$0 --output FILE [--mode maven|maven-aggregate|gradle|cli|coordinate] …" ;;
  esac
done

[[ -n "$OUTPUT_FILE" ]] || usage "$0 --output FILE ..."

write_coordinate_sbom() {
  local group_id="$1" artifact_id="$2" version="$3" out="$4"
  local purl
  purl="$(purl_for_coordinate "$group_id" "$artifact_id" "$version")"
  jq -n \
    --arg group "$group_id" \
    --arg name "$artifact_id" \
    --arg version "$version" \
    --arg purl "$purl" \
    --arg bom_ref "$purl" \
    '{
      bomFormat: "CycloneDX",
      specVersion: "1.5",
      version: 1,
      metadata: {
        component: {
          type: "library",
          "bom-ref": $bom_ref,
          group: $group,
          name: $name,
          version: $version,
          purl: $purl
        }
      },
      components: []
    }' >"$out"
}

case "$MODE" in
  maven)
    require_cmd mvn
    (cd "$MODULE_DIR" && mvn "org.cyclonedx:cyclonedx-maven-plugin:${CYCLONEDX_PLUGIN_VERSION}:makeBom" \
      -DoutputFormat=json -DoutputName=bom -q)
    cp "$MODULE_DIR/target/bom.json" "$OUTPUT_FILE"
    ;;
  maven-aggregate)
    require_cmd mvn
    (cd "$MODULE_DIR" && mvn "org.cyclonedx:cyclonedx-maven-plugin:${CYCLONEDX_PLUGIN_VERSION}:makeAggregateBom" \
      -DoutputFormat=json -DoutputName=bom -q)
    cp "$MODULE_DIR/target/bom.json" "$OUTPUT_FILE"
    ;;
  gradle)
    require_cmd jq
    REPO_DIR="${REPO_DIR:-$(cd "$MODULE_DIR/.." && pwd)}"
    # Spring Framework 5.3 ships Gradle 7.5.1 — cannot run under JDK 21+.
    if [[ "$REPO_DIR" == *spring* ]]; then
      ensure_spring_java_home
    else
      ensure_java_home || true
    fi
    module_name="$(basename "$MODULE_DIR")"
    [[ -x "$REPO_DIR/gradlew" ]] || {
      echo "error: gradlew not found in --repo-dir ${REPO_DIR}" >&2
      exit 1
    }
    [[ -f "$GRADLE_INIT" ]] || {
      echo "error: missing CycloneDX init script: ${GRADLE_INIT}" >&2
      exit 1
    }
    gradle_args=(--no-daemon -I "$GRADLE_INIT")
    if [[ "$REPO_DIR" == *spring* && -f "$SPRING_JDK_COMPAT_INIT" ]]; then
      gradle_args+=(-I "$SPRING_JDK_COMPAT_INIT")
    fi
    gradle_args+=(":${module_name}:cyclonedxBom")
    if [[ -n "$VERSION" ]]; then
      gradle_args+=(-Pversion="$VERSION")
    fi
    if (
      cd "$REPO_DIR" &&
      ./gradlew "${gradle_args[@]}"
    ); then
      bom_src=""
      for cand in \
        "$MODULE_DIR/build/reports/bom.json" \
        "$MODULE_DIR/build/reports/cyclonedx/bom.json" \
        "$MODULE_DIR/build/cyclonedx/bom.json"; do
        if [[ -f "$cand" ]]; then
          bom_src="$cand"
          break
        fi
      done
      if [[ -n "$bom_src" ]]; then
        cp "$bom_src" "$OUTPUT_FILE"
      else
        echo "warn: cyclonedxBom ran but bom.json not found; falling back to coordinate SBOM" >&2
        [[ -n "$GROUP_ID" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || {
          echo "error: pass --group-id --artifact-id --version for coordinate fallback" >&2
          exit 1
        }
        write_coordinate_sbom "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$OUTPUT_FILE"
      fi
    else
      echo "warn: gradle cyclonedxBom failed; falling back to coordinate SBOM" >&2
      [[ -n "$GROUP_ID" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || {
        echo "error: pass --group-id --artifact-id --version for coordinate fallback" >&2
        exit 1
      }
      write_coordinate_sbom "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$OUTPUT_FILE"
    fi
    ;;
  cli)
    require_cmd cyclonedx-cli
    [[ -n "$JAR_FILE" && -f "$JAR_FILE" ]] || usage "$0 --mode cli --jar FILE --output FILE"
    cyclonedx-cli generate \
      --input-type jar \
      --input-file "$JAR_FILE" \
      --output-file "$OUTPUT_FILE" \
      --output-format json
    ;;
  coordinate)
    require_cmd jq
    [[ -n "$GROUP_ID" && -n "$ARTIFACT_ID" && -n "$VERSION" ]] || \
      usage "$0 --mode coordinate --group-id G --artifact-id A --version V --output FILE"
    write_coordinate_sbom "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$OUTPUT_FILE"
    ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    exit 1
    ;;
esac

echo "wrote $OUTPUT_FILE"

if command -v cyclonedx >/dev/null 2>&1; then
  cyclonedx validate --input-file "$OUTPUT_FILE" --input-format json --input-version v1_5 || true
fi
