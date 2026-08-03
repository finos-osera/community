#!/usr/bin/env bash
# Shared helpers for release-pilot scripts.
set -euo pipefail

release_pilot_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$dir"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: required command not found: $cmd" >&2
    exit 1
  }
}

# True when DIR is a usable git work tree (rejects empty/husk .git leftovers).
git_worktree_ok() {
  local dir="$1"
  [[ -d "$dir/.git" ]] || return 1
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Clone REPO_URL into WORK_DIR, or re-clone when WORK_DIR has a broken .git husk.
# Optional 3rd arg is a log label (default: ensure-git-clone).
ensure_git_clone() {
  local work_dir="$1" repo_url="$2" label="${3:-ensure-git-clone}"

  require_cmd git

  if git_worktree_ok "$work_dir"; then
    return 0
  fi

  if [[ -e "$work_dir" ]]; then
    echo "${label}: ${work_dir} is not a valid git work tree — removing and re-cloning" >&2
    rm -rf "$work_dir"
  fi

  echo "${label}: cloning ${repo_url} → ${work_dir}" >&2
  git clone "$repo_url" "$work_dir" >&2

  git_worktree_ok "$work_dir" || {
    echo "error: clone succeeded but ${work_dir} is still not a valid git work tree" >&2
    return 1
  }
}

manifest_to_json() {
  local manifest="$1"
  yaml_to_json "$manifest"
}

yaml_to_json() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    yq -o=json '.' "$file"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "error: need yq or python3 with PyYAML to read manifest YAML "
        "(brew install yq / pip install pyyaml)\n"
    )
    raise SystemExit(1)

print(json.dumps(yaml.safe_load(open(sys.argv[1], encoding="utf-8"))))
PY
    return 0
  fi
  echo "error: need yq or python3 (with PyYAML) to read manifest YAML" >&2
  return 1
}

json_to_yaml() {
  if command -v yq >/dev/null 2>&1; then
    yq -P '.'
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "error: need yq or python3 with PyYAML to write manifest YAML "
        "(brew install yq / pip install pyyaml)\n"
    )
    raise SystemExit(1)

data = json.load(sys.stdin)
print(
    yaml.safe_dump(
        data,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    )
)
PY
    return 0
  fi
  echo "error: need yq or python3 (with PyYAML) to write manifest YAML" >&2
  return 1
}

manifest_field() {
  local manifest="$1" jq_filter="$2"
  manifest_to_json "$manifest" | jq -r "$jq_filter"
}

purl_for_coordinate() {
  local groupId="$1" artifactId="$2" version="$3"
  local encoded_version="${version//+/%2B}"
  printf 'pkg:maven/%s/%s@%s' "$groupId" "$artifactId" "$encoded_version"
}

usage() {
  echo "usage: $*" >&2
  exit 1
}

load_nexus_config() {
  local root preset_skip preset_url preset_repo
  root="$(release_pilot_root)"
  # Preserve caller exports — config file supplies defaults only.
  preset_skip="${OSERA_SKIP_SIGN-}"
  preset_url="${NEXUS_URL-}"
  preset_repo="${REPOSITORY_ID-}"
  if [[ -f "$root/config/nexus-playground.env" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$root/config/nexus-playground.env"
    set +a
  fi
  [[ -n "$preset_skip" ]] && OSERA_SKIP_SIGN="$preset_skip"
  [[ -n "$preset_url" ]] && NEXUS_URL="$preset_url"
  [[ -n "$preset_repo" ]] && REPOSITORY_ID="$preset_repo"
  export NEXUS_URL="${NEXUS_URL:-https://finos-osera.repo.sonatype.app/repository/playground/}"
  export REPOSITORY_ID="${REPOSITORY_ID:-osera-playground}"
  export OSERA_SKIP_SIGN="${OSERA_SKIP_SIGN:-1}"
}

# Populate NEXUS_USERNAME / NEXUS_PASSWORD from env or ~/.m2/settings.xml.
load_nexus_credentials() {
  if [[ -n "${NEXUS_USERNAME:-}" && -n "${NEXUS_PASSWORD:-}" ]]; then
    return 0
  fi
  local settings="${M2_SETTINGS:-$HOME/.m2/settings.xml}"
  [[ -f "$settings" ]] || {
    echo "error: set NEXUS_USERNAME/NEXUS_PASSWORD or provide $settings" >&2
    return 1
  }
  require_cmd python3
  eval "$(
    REPOSITORY_ID="$REPOSITORY_ID" SETTINGS="$settings" python3 - <<'PY'
import os
import shlex
import xml.etree.ElementTree as ET

settings = os.environ["SETTINGS"]
repo_id = os.environ["REPOSITORY_ID"]
root = ET.parse(settings).getroot()
for server in root.findall("servers/server"):
    if (server.findtext("id") or "") != repo_id:
        continue
    user = server.findtext("username") or ""
    password = server.findtext("password") or ""
    if not user or not password:
        raise SystemExit(f"error: empty credentials for <id>{repo_id}</id> in {settings}")
    print(f"export NEXUS_USERNAME={shlex.quote(user)}")
    print(f"export NEXUS_PASSWORD={shlex.quote(password)}")
    raise SystemExit(0)
raise SystemExit(f"error: no <server><id>{repo_id}</id> in {settings}")
PY
  )"
}

nexus_gav_base_url() {
  local group_id="$1" artifact_id="$2" version="$3"
  local group_path="${group_id//.//}"
  printf '%s%s/%s/%s' "${NEXUS_URL%/}/" "$group_path" "$artifact_id" "$version"
}

skip_sign_by_default() {
  case "${OSERA_SKIP_SIGN:-1}" in
    1|true|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# Print staged artifact paths that must receive vendor + FINOS detached signatures.
# packaging: jar (default) | pom (BOM / pom-only; no .jar target)
staged_sign_targets() {
  local staging="$1" artifact_id="$2" version="$3" packaging="${4:-jar}"
  local prefix="$staging/${artifact_id}-${version}"
  if [[ "$packaging" == "jar" ]]; then
    printf '%s\n' "${prefix}.jar"
  fi
  printf '%s\n' \
    "${prefix}.pom" \
    "${prefix}-cyclonedx.json" \
    "${prefix}.openvex.json" \
    "${prefix}-recipient-guidance.yaml"
}

# Echo existing staged files that require signatures (skip missing optional sidecars).
existing_sign_targets() {
  local staging="$1" artifact_id="$2" version="$3" packaging="${4:-jar}" file
  while IFS= read -r file; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done < <(staged_sign_targets "$staging" "$artifact_id" "$version" "$packaging")
}

require_signature_sidecars() {
  local file="$1"
  [[ -f "${file}.asc" ]] || {
    echo "error: missing vendor signature: ${file}.asc" >&2
    return 1
  }
  [[ -f "${file}.asc.finos" ]] || {
    echo "error: missing FINOS co-signature: ${file}.asc.finos" >&2
    return 1
  }
}

java_major_version() {
  local java_home="$1"
  local ver major
  ver="$("$java_home/bin/java" -version 2>&1 | awk -F '"' '/version/ { print $2; exit }')"
  if [[ "$ver" == 1.* ]]; then
    major="${ver#1.}"
    major="${major%%.*}"
  else
    major="${ver%%.*}"
  fi
  printf '%s\n' "$major"
}

# backpatch-h2 targets Java 7 bytecode; use JDK 17 for Maven (JDK 21+ rejects source 7).
ensure_h2_java_home() {
  local major candidate homebrew_prefix="/opt/homebrew"

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    major="$(java_major_version "$JAVA_HOME")"
    if [[ "$major" == "17" ]]; then
      echo "java: using JAVA_HOME=${JAVA_HOME} (JDK 17 for backpatch-h2)" >&2
      return 0
    fi
    echo "warn: JAVA_HOME=${JAVA_HOME} is JDK ${major}; backpatch-h2 requires JDK 17 for Maven" >&2
  else
    echo "java: JAVA_HOME is not set — selecting JDK 17 for backpatch-h2…" >&2
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    if candidate="$(/usr/libexec/java_home -v 17 2>/dev/null)" && [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      echo "java: using JAVA_HOME=${JAVA_HOME} (via /usr/libexec/java_home -v 17)" >&2
      return 0
    fi
  fi

  if [[ ! -d "$homebrew_prefix/opt" && -d /usr/local/opt ]]; then
    homebrew_prefix="/usr/local"
  fi
  candidate="${homebrew_prefix}/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
  if [[ -x "$candidate/bin/java" ]]; then
    export JAVA_HOME="$candidate"
    echo "java: using JAVA_HOME=${JAVA_HOME} (via Homebrew openjdk@17)" >&2
    return 0
  fi

  echo "error: JDK 17 is required to build backpatch-h2 (POM targets Java 7; JDK 21+ cannot compile it)." >&2
  echo "action: install JDK 17, then run:" >&2
  echo "  export JAVA_HOME=\$(/usr/libexec/java_home -v 17)" >&2
  echo "  brew install openjdk@17   # if missing on macOS" >&2
  return 1
}

# Accept candidate JAVA_HOME only when its major version is in the allow-list.
# macOS /usr/libexec/java_home -v 1.8 can return a newer JDK when 8 is missing.
spring_java_home_usable() {
  local home="$1" major
  [[ -x "${home}/bin/java" ]] || return 1
  major="$(java_major_version "$home")"
  case "$major" in
    8|11|17) return 0 ;;
    *) return 1 ;;
  esac
}

# backpatch-spring-framework 5.3.x: Gradle 7.5.1 needs a JDK ≤ 17 to *run*.
# Prefer 8 (.sdkmanrc), then 11, then 17. JDK 17 uses spring-jdk-compat.init.gradle.
ensure_spring_java_home() {
  local major candidate homebrew_prefix="/opt/homebrew" version brew_pkg

  if [[ -n "${JAVA_HOME:-}" ]] && spring_java_home_usable "$JAVA_HOME"; then
    major="$(java_major_version "$JAVA_HOME")"
    echo "java: using JAVA_HOME=${JAVA_HOME} (JDK ${major} for backpatch-spring-framework)" >&2
    return 0
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    major="$(java_major_version "$JAVA_HOME")"
    echo "warn: JAVA_HOME=${JAVA_HOME} is JDK ${major}; Gradle 7.5.1 needs JDK 8/11/17" >&2
  else
    echo "java: selecting JDK 8/11/17 for backpatch-spring-framework…" >&2
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    for version in 1.8 11 17; do
      candidate="$(/usr/libexec/java_home -v "$version" 2>/dev/null || true)"
      if spring_java_home_usable "$candidate"; then
        major="$(java_major_version "$candidate")"
        # Reject false matches (e.g. -v 1.8 → JDK 23 when 8 is not installed).
        case "$version" in
          1.8) [[ "$major" == "8" ]] || continue ;;
          11) [[ "$major" == "11" ]] || continue ;;
          17) [[ "$major" == "17" ]] || continue ;;
        esac
        export JAVA_HOME="$candidate"
        echo "java: using JAVA_HOME=${JAVA_HOME} (JDK ${major} via /usr/libexec/java_home -v ${version})" >&2
        return 0
      fi
    done
  fi

  if [[ ! -d "$homebrew_prefix/opt" && -d /usr/local/opt ]]; then
    homebrew_prefix="/usr/local"
  fi
  for brew_pkg in openjdk@8 openjdk@11 openjdk@17; do
    candidate="${homebrew_prefix}/opt/${brew_pkg}/libexec/openjdk.jdk/Contents/Home"
    if spring_java_home_usable "$candidate"; then
      export JAVA_HOME="$candidate"
      echo "java: using JAVA_HOME=${JAVA_HOME} (via Homebrew ${brew_pkg})" >&2
      return 0
    fi
  done

  # Homebrew Cellar path (versioned) when the opt symlink is missing.
  for candidate in \
    "${homebrew_prefix}"/Cellar/openjdk@17/*/libexec/openjdk.jdk/Contents/Home \
    "${homebrew_prefix}"/Cellar/openjdk@11/*/libexec/openjdk.jdk/Contents/Home \
    "${homebrew_prefix}"/Cellar/openjdk@8/*/libexec/openjdk.jdk/Contents/Home; do
    if spring_java_home_usable "$candidate"; then
      export JAVA_HOME="$candidate"
      echo "java: using JAVA_HOME=${JAVA_HOME} (via Homebrew Cellar)" >&2
      return 0
    fi
  done

  echo "error: JDK 8/11/17 is required to build backpatch-spring-framework (Gradle 7.5.1 cannot run on JDK 21+)." >&2
  echo "action: install JDK 17, then run:" >&2
  echo "  brew install openjdk@17" >&2
  echo "  export JAVA_HOME=\$(/usr/libexec/java_home -v 17)" >&2
  return 1
}

# Resolve JAVA_HOME when unset (macOS Homebrew, /usr/libexec/java_home, PATH).
ensure_java_home() {
  local candidate="" homebrew_prefix="/opt/homebrew"

  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    echo "java: using JAVA_HOME=${JAVA_HOME}" >&2
    return 0
  fi

  echo "java: JAVA_HOME is not set — attempting auto-detection…" >&2

  if [[ -x /usr/libexec/java_home ]]; then
    local version
    for version in 17 21 11 1.8; do
      if candidate="$(/usr/libexec/java_home -v "$version" 2>/dev/null)" && [[ -x "$candidate/bin/java" ]]; then
        export JAVA_HOME="$candidate"
        echo "java: detected JAVA_HOME=${JAVA_HOME} (via /usr/libexec/java_home -v ${version})" >&2
        return 0
      fi
    done
    if candidate="$(/usr/libexec/java_home 2>/dev/null)" && [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      echo "java: detected JAVA_HOME=${JAVA_HOME} (via /usr/libexec/java_home)" >&2
      return 0
    fi
    echo "java: /usr/libexec/java_home found no usable JVM" >&2
  fi

  if [[ ! -d "$homebrew_prefix/opt" && -d /usr/local/opt ]]; then
    homebrew_prefix="/usr/local"
  fi

  local brew_pkg
  for brew_pkg in openjdk@17 openjdk@21 openjdk@11 openjdk@23 openjdk; do
    candidate="${homebrew_prefix}/opt/${brew_pkg}/libexec/openjdk.jdk/Contents/Home"
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      echo "java: detected JAVA_HOME=${JAVA_HOME} (via Homebrew ${brew_pkg})" >&2
      return 0
    fi
  done

  if command -v java >/dev/null 2>&1; then
    candidate="$(cd "$(dirname "$(command -v java)")/.." && pwd)"
    if [[ -x "$candidate/bin/java" ]]; then
      export JAVA_HOME="$candidate"
      echo "java: detected JAVA_HOME=${JAVA_HOME} (via java on PATH)" >&2
      return 0
    fi
  fi

  echo "error: could not determine JAVA_HOME." >&2
  echo "action: install a JDK, then run one of:" >&2
  echo "  export JAVA_HOME=\$(/usr/libexec/java_home)" >&2
  echo "  export JAVA_HOME=\"/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home\"" >&2
  echo "  export JAVA_HOME=\"/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home\"" >&2
  return 1
}
