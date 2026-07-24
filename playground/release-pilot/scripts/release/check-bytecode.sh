#!/usr/bin/env bash
# REL-002 bytecode compatibility check (stub — compares major class file versions).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

JAR=""
BASELINE_JAR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jar) JAR="$2"; shift 2 ;;
    --baseline-jar) BASELINE_JAR="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 --jar FILE [--baseline-jar FILE]"
      echo "REL-002: fails when major bytecode version differs from baseline."
      exit 0
      ;;
    *) usage "$0 --jar FILE [--baseline-jar FILE]" ;;
  esac
done

[[ -n "$JAR" && -f "$JAR" ]] || usage "$0 --jar FILE [--baseline-jar FILE]"
require_cmd javap

class_version() {
  local jar="$1"
  local sample
  sample="$(jar tf "$jar" | grep -E '\.class$' | grep -v '\$' | head -1)"
  [[ -n "$sample" ]] || {
    echo "error: no .class files in $jar" >&2
    return 1
  }
  javap -verbose -classpath "$jar" "${sample%.class}" | awk '/major version/ { print $3; exit }'
}

current="$(class_version "$JAR")"
echo "jar major version: $current"

if [[ -n "$BASELINE_JAR" ]]; then
  baseline="$(class_version "$BASELINE_JAR")"
  echo "baseline major version: $baseline"
  [[ "$current" == "$baseline" ]] || {
    echo "error: REL-002 bytecode mismatch ($current != $baseline)" >&2
    exit 1
  }
  echo "REL-002 check passed"
else
  echo "warn: no --baseline-jar supplied; recorded major version only"
fi
