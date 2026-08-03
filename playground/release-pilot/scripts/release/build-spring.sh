#!/usr/bin/env bash
# Build backpatch-spring-framework pilot tag locally (no repo edits).
#
# Gradle multi-module: assembles all spring-* jars + framework-bom POM, overrides
# project version to the REL-003 publish version (tag without leading v).
#
# When sourced via: eval "$(playground/release-pilot/scripts/release/build-spring.sh)"
# only variable assignments are printed to stdout; logs go to stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TAG="${TAG:-v5.3.39+backpatch.001}"
WORK_DIR="${WORK_DIR:-/tmp/backpatch-spring-framework-build}"
REPO_URL="${REPO_URL:-https://github.com/finos-osera/backpatch-spring-framework.git}"
GROUP_ID="${GROUP_ID:-org.springframework}"
MODULES_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir) WORK_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --modules)
      MODULES_FILTER="$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF >&2
usage: $0 [--work-dir DIR] [--tag TAG] [--group-id G] [--modules LIST]

Build finos-osera/backpatch-spring-framework at TAG. Prints eval-safe exports:
  repo_dir=… tag=… group_id=… version=… modules_file=…

--modules is a comma-separated allowlist (default: all spring-* + framework-bom).

Requires: git, JDK 8/11/17 (17 preferred; auto-selected)

Example:
  eval "\$($0)"
EOF
      exit 0
      ;;
    *) echo "usage: $0 [--work-dir DIR] [--tag TAG] [--group-id G] [--modules LIST]" >&2; exit 1 ;;
  esac
done

require_cmd git
ensure_spring_java_home

VERSION="${TAG#v}"
MODULES_FILE="${WORK_DIR}/.osera-modules.tsv"

echo "build-spring: tag=${TAG} version=${VERSION} work_dir=${WORK_DIR}" >&2

ensure_git_clone "$WORK_DIR" "$REPO_URL" "build-spring"

echo "build-spring: fetching tags and checking out ${TAG}" >&2
git -C "$WORK_DIR" fetch --tags >&2
git -C "$WORK_DIR" checkout "$TAG" >&2

[[ -x "$WORK_DIR/gradlew" ]] || {
  echo "error: missing gradlew in ${WORK_DIR}" >&2
  exit 1
}

# Discover publishable modules: spring-* dirs + framework-bom (excludes integration-tests).
discover_modules() {
  local dir name
  for dir in "$WORK_DIR"/spring-*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    [[ -f "$dir/${name}.gradle" ]] || continue
    printf '%s\n' "$name"
  done
  if [[ -d "$WORK_DIR/framework-bom" && -f "$WORK_DIR/framework-bom/framework-bom.gradle" ]]; then
    printf '%s\n' "framework-bom"
  fi
}

filter_modules() {
  local name w
  local -a all=() wanted=()
  while IFS= read -r name; do
    [[ -n "$name" ]] && all+=("$name")
  done < <(discover_modules)

  if [[ -z "$MODULES_FILTER" ]]; then
    printf '%s\n' "${all[@]}"
    return 0
  fi

  IFS=',' read -r -a wanted <<< "$MODULES_FILTER"
  for name in "${all[@]}"; do
    for w in "${wanted[@]}"; do
      w="${w// /}"
      if [[ "$name" == "$w" || ( "$name" == "framework-bom" && "$w" == "spring-framework-bom" ) ]]; then
        printf '%s\n' "$name"
        break
      fi
    done
  done
}

MODULES=()
while IFS= read -r _mod; do
  [[ -n "$_mod" ]] && MODULES+=("$_mod")
done < <(filter_modules)
[[ ${#MODULES[@]} -gt 0 ]] || {
  echo "error: no modules selected to build" >&2
  exit 1
}

echo "build-spring: modules (${#MODULES[@]}): ${MODULES[*]}" >&2

# Gradle project path for each module directory name.
gradle_project() {
  local name="$1"
  printf ':%s' "$name"
}

# ArtifactId published to Maven (BOM uses spring-framework-bom).
artifact_id_for() {
  local name="$1"
  if [[ "$name" == "framework-bom" ]]; then
    printf 'spring-framework-bom\n'
  else
    printf '%s\n' "$name"
  fi
}

packaging_for() {
  local name="$1"
  if [[ "$name" == "framework-bom" ]]; then
    printf 'pom\n'
  else
    printf 'jar\n'
  fi
}

gradle_tasks=(assemble)
for _mod in "${MODULES[@]}"; do
  gradle_tasks+=("$(gradle_project "$_mod"):generatePomFileForMavenJavaPublication")
done

SPRING_JDK_COMPAT_INIT="${SPRING_JDK_COMPAT_INIT:-$ROOT/templates/spring-jdk-compat.init.gradle}"
gradle_init_args=()
if [[ -f "$SPRING_JDK_COMPAT_INIT" ]]; then
  gradle_init_args+=(-I "$SPRING_JDK_COMPAT_INIT")
  echo "build-spring: applying JDK compat init (${SPRING_JDK_COMPAT_INIT})" >&2
fi

echo "build-spring: ./gradlew -Pversion=${VERSION} assemble + generatePom… (JAVA_HOME=${JAVA_HOME})" >&2
# Develocity/build-scan may warn without credentials; do not fail the build on that.
if ! (
  cd "$WORK_DIR" &&
  ./gradlew --no-daemon \
    "${gradle_init_args[@]}" \
    -Pversion="$VERSION" \
    -x test -x check \
    "${gradle_tasks[@]}"
) >&2; then
  echo "error: gradle build failed" >&2
  echo "action: prefer JDK 8 (Spring 5.3.x .sdkmanrc), or JDK 17 with spring-jdk-compat.init.gradle:" >&2
  echo "  brew install openjdk@8 && export JAVA_HOME=\$(/usr/libexec/java_home -v 1.8)" >&2
  echo "  export JAVA_HOME=\$(/usr/libexec/java_home -v 17)   # uses templates/spring-jdk-compat.init.gradle" >&2
  exit 1
fi

: >"$MODULES_FILE"
for _mod in "${MODULES[@]}"; do
  artifact_id="$(artifact_id_for "$_mod")"
  packaging="$(packaging_for "$_mod")"
  module_dir="${WORK_DIR}/${_mod}"
  pom_path="${module_dir}/build/publications/mavenJava/pom-default.xml"
  jar_path=""

  [[ -f "$pom_path" ]] || {
    echo "error: missing generated POM for ${_mod}: ${pom_path}" >&2
    exit 1
  }

  if [[ "$packaging" == "jar" ]]; then
    # Prefer versioned jar; exclude -sources / -javadoc / plain classifiers.
    jar_path="$(
      find "${module_dir}/build/libs" -maxdepth 1 -type f -name "${artifact_id}-${VERSION}.jar" 2>/dev/null | head -1
    )"
    if [[ -z "$jar_path" ]]; then
      jar_path="$(
        find "${module_dir}/build/libs" -maxdepth 1 -type f -name "${artifact_id}-*.jar" ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name '*-plain.jar' 2>/dev/null | head -1
      )"
    fi
    [[ -n "$jar_path" && -f "$jar_path" ]] || {
      echo "error: no JAR found for ${_mod} under ${module_dir}/build/libs/" >&2
      exit 1
    }
  fi

  # TSV: module_dir artifact_id packaging jar pom
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$module_dir" "$artifact_id" "$packaging" "$jar_path" "$pom_path" >>"$MODULES_FILE"
  echo "build-spring: ${artifact_id} (${packaging}) ok" >&2
done

echo "build-spring: wrote modules file ${MODULES_FILE} ($(wc -l <"$MODULES_FILE" | tr -d ' ') rows)" >&2

# stdout only — safe for eval "$($0)"
# Export JAVA_HOME so follow-on publish/SBOM Gradle steps don't fall back to JDK 23.
printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
printf 'repo_dir=%q\n' "$WORK_DIR"
printf 'tag=%q\n' "$TAG"
printf 'group_id=%q\n' "$GROUP_ID"
printf 'version=%q\n' "$VERSION"
printf 'modules_file=%q\n' "$MODULES_FILE"
