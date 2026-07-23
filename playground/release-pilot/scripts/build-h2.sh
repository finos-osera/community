#!/usr/bin/env bash
# Build backpatch-h2 pilot tag locally (no repo edits).
#
# Uses Maven only (no ./build.sh compile — that target fails on JDK 9+).
# Requires JDK 17; JDK 21+ cannot compile the Java-7-target h2 POM.
#
# When sourced via: eval "$(playground/release-pilot/scripts/build-h2.sh)"
# only variable assignments are printed to stdout; logs go to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TAG="${TAG:-v1.4.200+backpatch.001}"
WORK_DIR="${WORK_DIR:-/tmp/backpatch-h2-build}"
REPO_URL="${REPO_URL:-https://github.com/finos-osera/backpatch-h2.git}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir) WORK_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF >&2
usage: $0 [--work-dir DIR] [--tag TAG]

Build finos-osera/backpatch-h2 at TAG. Prints eval-safe exports to stdout:
  module_dir=… jar=… pom=…

Requires: git, mvn, JDK 17 (auto-selected; JDK 23 will be overridden)

Example:
  eval "\$($0)"
EOF
      exit 0
      ;;
    *) echo "usage: $0 [--work-dir DIR] [--tag TAG]" >&2; exit 1 ;;
  esac
done

require_cmd git
require_cmd mvn
ensure_h2_java_home

echo "build-h2: tag=${TAG} work_dir=${WORK_DIR}" >&2

if [[ ! -d "$WORK_DIR/.git" ]]; then
  echo "build-h2: cloning ${REPO_URL} → ${WORK_DIR}" >&2
  git clone "$REPO_URL" "$WORK_DIR" >&2
fi

echo "build-h2: fetching tags and checking out ${TAG}" >&2
git -C "$WORK_DIR" fetch --tags >&2
git -C "$WORK_DIR" checkout "$TAG" >&2

module_dir="${WORK_DIR}/h2"

echo "build-h2: running mvn clean package -Dmaven.test.skip=true (JAVA_HOME=${JAVA_HOME})" >&2
echo "build-h2: skipping ./build.sh compile (incompatible with modern JDKs; Maven path per h2/MAVEN.md)" >&2
if ! (cd "$module_dir" && mvn clean package -Dmaven.test.skip=true >&2); then
  echo "error: mvn package failed" >&2
  echo "action: use JDK 17 — export JAVA_HOME=\$(/usr/libexec/java_home -v 17)" >&2
  exit 1
fi

jar_path="$(ls -1 "${module_dir}"/target/h2-*.jar 2>/dev/null | head -1)"
if [[ -z "$jar_path" || ! -f "$jar_path" ]]; then
  echo "error: no JAR found under ${module_dir}/target/" >&2
  exit 1
fi

echo "build-h2: built ${jar_path}" >&2

# stdout only — safe for eval "$($0)"
printf 'module_dir=%q\n' "$module_dir"
printf 'jar=%q\n' "$jar_path"
printf 'pom=%q\n' "${module_dir}/pom.xml"
printf 'repo_dir=%q\n' "$WORK_DIR"
printf 'tag=%q\n' "$TAG"
