#!/usr/bin/env bash
# End-to-end Spring (Gradle multi-module) pilot pipeline.
# Builds are done by build-spring.sh; this script publishes every row in modules_file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$ROOT/scripts"
RELEASE="$SCRIPTS/release"
PUBLISH="$SCRIPTS/publish"
SIGN="$SCRIPTS/sign"

# shellcheck source=../lib/common.sh
source "$SCRIPTS/lib/common.sh"

REPO_DIR="${REPO_DIR:-${repo_dir:-}}"
TAG="${TAG:-${tag:-}}"
GROUP_ID="${GROUP_ID:-${group_id:-org.springframework}}"
MODULES_FILE="${MODULES_FILE:-${modules_file:-}}"
VERSION="${VERSION:-${version:-}}"
STAGING_ROOT=""
SKIP_SIGN=""
SKIP_DEPLOY=false
SKIP_VERIFY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --modules-file) MODULES_FILE="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --staging) STAGING_ROOT="$2"; shift 2 ;;
    --skip-sign) SKIP_SIGN=true; shift ;;
    --sign) SKIP_SIGN=false; shift ;;
    --skip-deploy) SKIP_DEPLOY=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    --dry-run) DRY_RUN=true; SKIP_DEPLOY=true; shift ;;
    -h|--help)
      cat <<EOF
usage: $0 --staging DIR --repo-dir DIR --tag TAG --modules-file FILE
       [--group-id G] [--version V] [--skip-sign|--sign]
       [--skip-deploy] [--skip-verify] [--dry-run]

Publishes every spring-* module (+ spring-framework-bom) listed in modules_file
produced by scripts/release/build-spring.sh.

Example:
  eval "\$(scripts/release/build-spring.sh)"
  $0 --repo-dir "\$repo_dir" --tag "\$tag" --modules-file "\$modules_file" \\
     --staging /tmp/osera-staging-spring
EOF
      exit 0
      ;;
    *) echo "usage: $0 --help" >&2; exit 1 ;;
  esac
done

for req in STAGING_ROOT REPO_DIR TAG MODULES_FILE; do
  if [[ -z "${!req}" ]]; then
    echo "error: missing required argument for $req" >&2
    exit 1
  fi
done

[[ -f "$MODULES_FILE" ]] || {
  echo "error: modules file not found: $MODULES_FILE" >&2
  echo "hint: eval \"\$(scripts/release/build-spring.sh)\" first" >&2
  exit 1
}

VERSION="${VERSION:-${TAG#v}}"
load_nexus_config
# Gradle 7.5.1 (SBOM / any re-invoke) cannot run on JDK 21+; match build-spring.sh.
ensure_spring_java_home

if [[ -z "$SKIP_SIGN" ]]; then
  if skip_sign_by_default; then
    SKIP_SIGN=true
  else
    SKIP_SIGN=false
  fi
fi

mkdir -p "$STAGING_ROOT"
published=0
failed=0

publish_one() {
  local module_dir="$1" artifact_id="$2" packaging="$3" jar="$4" pom="$5"
  local staging manifest sbom_tmp version_dir

  staging="${STAGING_ROOT}/${artifact_id}"
  mkdir -p "$staging"
  version_dir="/tmp/osera-releases/spring-framework/${artifact_id}"
  mkdir -p "$version_dir"

  echo "==== publish ${GROUP_ID}:${artifact_id}:${VERSION} (packaging=${packaging}) ====" >&2

  manifest="$("$RELEASE/generate-release-manifest.sh" \
    --repo-dir "$REPO_DIR" \
    --tag "$TAG" \
    --group-id "$GROUP_ID" \
    --artifact-id "$artifact_id" \
    --output "${version_dir}/${VERSION}.yaml")"

  "$RELEASE/generate-openvex.sh" --manifest "$manifest"

  sbom_tmp="$(mktemp "${TMPDIR:-/tmp}/osera-sbom.XXXXXX.json")"
  # Coordinate SBOM by default: 23× Gradle cyclonedxBom is slow and re-invokes
  # Gradle under the operator shell JDK. Use generate-sbom.sh --mode gradle for a
  # deeper BOM when needed.
  "$RELEASE/generate-sbom.sh" \
    --mode coordinate \
    --group-id "$GROUP_ID" \
    --artifact-id "$artifact_id" \
    --version "$VERSION" \
    --output "$sbom_tmp"
  if [[ "$packaging" == "jar" ]]; then
    "$RELEASE/check-bytecode.sh" --jar "$jar"
  fi

  stage_args=(
    --manifest "$manifest"
    --staging "$staging"
    --pom "$pom"
    --sbom "$sbom_tmp"
    --packaging "$packaging"
  )
  if [[ "$packaging" == "jar" ]]; then
    stage_args+=(--jar "$jar")
  fi
  "$PUBLISH/stage-artifacts.sh" "${stage_args[@]}"
  rm -f "$sbom_tmp"

  if ! $SKIP_SIGN; then
    "$SIGN/vendor-sign.sh" \
      --staging "$staging" --artifact-id "$artifact_id" --version "$VERSION" --packaging "$packaging"
    "$SIGN/finos-cosign.sh" \
      --staging "$staging" --artifact-id "$artifact_id" --version "$VERSION" --packaging "$packaging"
  fi

  if ! $SKIP_DEPLOY; then
    deploy_args=(--manifest "$manifest" --staging "$staging" --packaging "$packaging")
    $DRY_RUN && deploy_args+=(--dry-run)
    "$PUBLISH/publish-to-nexus.sh" "${deploy_args[@]}"
  fi

  if ! $SKIP_VERIFY; then
    verify_args=(--manifest "$manifest" --staging "$staging" --packaging "$packaging")
    $SKIP_DEPLOY && verify_args+=(--skip-nexus)
    "$PUBLISH/verify-publish.sh" "${verify_args[@]}"
  fi

  echo "ok ${GROUP_ID}:${artifact_id}:${VERSION}"
}

while IFS=$'\t' read -r module_dir artifact_id packaging jar pom || [[ -n "${module_dir:-}" ]]; do
  [[ -n "${module_dir:-}" ]] || continue
  [[ "$module_dir" == \#* ]] && continue
  if publish_one "$module_dir" "$artifact_id" "$packaging" "$jar" "$pom"; then
    published=$((published + 1))
  else
    echo "error: failed ${artifact_id}" >&2
    failed=$((failed + 1))
  fi
done <"$MODULES_FILE"

echo "spring pipeline complete: published=${published} failed=${failed}"
[[ "$failed" -eq 0 ]]
