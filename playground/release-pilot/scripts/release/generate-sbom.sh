#!/usr/bin/env bash
# Generate CycloneDX SBOM without editing backpatch repo POMs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

MODE="maven"
MODULE_DIR="."
OUTPUT_FILE=""
JAR_FILE=""
CYCLONEDX_PLUGIN_VERSION="${CYCLONEDX_PLUGIN_VERSION:-2.9.1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --module-dir) MODULE_DIR="$2"; shift 2 ;;
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --jar) JAR_FILE="$2"; shift 2 ;;
    --aggregate) MODE="maven-aggregate"; shift ;;
    -h|--help)
      echo "usage: $0 --output FILE [--mode maven|maven-aggregate|cli] [--module-dir DIR] [--jar FILE]"
      exit 0
      ;;
    *) usage "$0 --output FILE [--mode maven|maven-aggregate|cli] [--module-dir DIR] [--jar FILE]" ;;
  esac
done

[[ -n "$OUTPUT_FILE" ]] || usage "$0 --output FILE ..."

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
  cli)
    require_cmd cyclonedx-cli
    [[ -n "$JAR_FILE" && -f "$JAR_FILE" ]] || usage "$0 --mode cli --jar FILE --output FILE"
    cyclonedx-cli generate \
      --input-type jar \
      --input-file "$JAR_FILE" \
      --output-file "$OUTPUT_FILE" \
      --output-format json
    ;;
  *)
    echo "error: unknown mode: $MODE" >&2
    exit 1
    ;;
esac

echo "wrote $OUTPUT_FILE"

if command -v cyclonedx >/dev/null 2>&1; then
  cyclonedx validate --input-file "$OUTPUT_FILE" --input-format json --input-version v1_5
fi
