#!/usr/bin/env bash
# End-to-end pilot pipeline: openvex → sbom → stage → sign → deploy → verify.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPTS="$ROOT/scripts"
RELEASE="$SCRIPTS/release"
PUBLISH="$SCRIPTS/publish"
SIGN="$SCRIPTS/sign"

MANIFEST=""
STAGING=""
MODULE_DIR=""
JAR=""
POM=""
REPO_DIR=""
TAG=""
GROUP_ID=""
ARTIFACT_ID=""
BASELINE_JAR=""
SKIP_SIGN=""
SKIP_DEPLOY=false
SKIP_VERIFY=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --group-id) GROUP_ID="$2"; shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --staging) STAGING="$2"; shift 2 ;;
    --module-dir) MODULE_DIR="$2"; shift 2 ;;
    --jar) JAR="$2"; shift 2 ;;
    --pom) POM="$2"; shift 2 ;;
    --baseline-jar) BASELINE_JAR="$2"; shift 2 ;;
    --skip-sign) SKIP_SIGN=true; shift ;;
    --sign) SKIP_SIGN=false; shift ;;
    --skip-deploy) SKIP_DEPLOY=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    --dry-run) DRY_RUN=true; SKIP_DEPLOY=true; shift ;;
    -h|--help)
      cat <<EOF
usage: $0 --staging DIR --module-dir DIR --jar JAR --pom POM
       [--repo-dir DIR --tag TAG --group-id G --artifact-id A]
       [--manifest PATH] [--baseline-jar FILE] [--skip-sign|--sign]
       [--skip-deploy] [--skip-verify] [--dry-run]

Generates the release manifest from git when --manifest is omitted, or when a
deprecated releases/h2/{version}.yaml path is passed after eval "\$(build-h2.sh)".

Signing is skipped by default (config/nexus-playground.env). Use --sign to enable
OpenPGP vendor + FINOS steps (see scripts/sign/ and signing-setup.md).
EOF
      exit 0
      ;;
    *) echo "usage: $0 --help" >&2; exit 1 ;;
  esac
done

for req in STAGING MODULE_DIR JAR POM; do
  if [[ -z "${!req}" ]]; then
    echo "error: missing required argument for $req" >&2
    exit 1
  fi
done

# Resolve git inputs from build-h2 eval (repo_dir, tag) or deprecated releases/h2/{version}.yaml paths.
REPO_DIR="${REPO_DIR:-${repo_dir:-}}"
TAG="${TAG:-${tag:-}}"

if [[ -n "$MANIFEST" && ! -f "$MANIFEST" ]]; then
  manifest_base="$(basename "$MANIFEST" .yaml)"
  if [[ "$manifest_base" =~ \+backpatch\. ]]; then
    REPO_DIR="${REPO_DIR:-/tmp/backpatch-h2-build}"
    TAG="${TAG:-v${manifest_base}}"
    GROUP_ID="${GROUP_ID:-com.h2database}"
    ARTIFACT_ID="${ARTIFACT_ID:-h2}"
    echo "warn: checked-in manifest removed ($MANIFEST); generating from git tag ${TAG}" >&2
    MANIFEST=""
  fi
fi

if [[ -z "$GROUP_ID" && -z "$ARTIFACT_ID" ]]; then
  if [[ "$REPO_DIR" == *backpatch-h2* ]] || [[ "$MODULE_DIR" == */h2 ]]; then
    GROUP_ID=com.h2database
    ARTIFACT_ID=h2
  fi
fi

if [[ -z "$MANIFEST" ]]; then
  if [[ -n "$REPO_DIR" && -n "$TAG" && -n "$GROUP_ID" && -n "$ARTIFACT_ID" ]]; then
    MANIFEST="$("$RELEASE/generate-release-manifest.sh" \
      --repo-dir "$REPO_DIR" \
      --tag "$TAG" \
      --group-id "$GROUP_ID" \
      --artifact-id "$ARTIFACT_ID")"
  else
    echo "error: pass --repo-dir --tag --group-id --artifact-id (or run build-h2.sh first)" >&2
    exit 1
  fi
elif [[ ! -f "$MANIFEST" ]]; then
  echo "error: manifest not found: $MANIFEST" >&2
  echo "hint: omit --manifest after eval \"\$(build-h2.sh)\" to generate from git" >&2
  exit 1
fi

# shellcheck source=../lib/common.sh
source "$SCRIPTS/lib/common.sh"
load_nexus_config

if [[ -z "$SKIP_SIGN" ]]; then
  if skip_sign_by_default; then
    SKIP_SIGN=true
  else
    SKIP_SIGN=false
  fi
fi

artifactId="$(manifest_field "$MANIFEST" '.coordinate.artifactId')"
version="$(manifest_field "$MANIFEST" '.coordinate.version')"
sbom_tmp="$(mktemp "${TMPDIR:-/tmp}/osera-sbom.XXXXXX.json")"
trap 'rm -f "$sbom_tmp"' EXIT

"$RELEASE/generate-openvex.sh" --manifest "$MANIFEST"
"$RELEASE/generate-sbom.sh" --mode maven --module-dir "$MODULE_DIR" --output "$sbom_tmp"

if [[ -n "$BASELINE_JAR" ]]; then
  "$RELEASE/check-bytecode.sh" --jar "$JAR" --baseline-jar "$BASELINE_JAR"
else
  "$RELEASE/check-bytecode.sh" --jar "$JAR"
fi

"$PUBLISH/stage-artifacts.sh" \
  --manifest "$MANIFEST" \
  --staging "$STAGING" \
  --jar "$JAR" \
  --pom "$POM" \
  --sbom "$sbom_tmp"

if ! $SKIP_SIGN; then
  "$SIGN/vendor-sign.sh" --staging "$STAGING" --artifact-id "$artifactId" --version "$version"
  "$SIGN/finos-cosign.sh" --staging "$STAGING" --artifact-id "$artifactId" --version "$version"
fi

if ! $SKIP_DEPLOY; then
  deploy_args=(--manifest "$MANIFEST" --staging "$STAGING")
  $DRY_RUN && deploy_args+=(--dry-run)
  "$PUBLISH/publish-to-nexus.sh" "${deploy_args[@]}"
fi

if ! $SKIP_VERIFY; then
  verify_args=(--manifest "$MANIFEST" --staging "$STAGING")
  $SKIP_DEPLOY && verify_args+=(--skip-nexus)
  "$PUBLISH/verify-publish.sh" "${verify_args[@]}"
fi

echo "pipeline complete"
