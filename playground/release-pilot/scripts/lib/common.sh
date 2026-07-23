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
  local root
  root="$(release_pilot_root)"
  if [[ -f "$root/config/nexus-playground.env" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$root/config/nexus-playground.env"
    set +a
  fi
  export NEXUS_URL="${NEXUS_URL:-https://finos-osera.repo.sonatype.app/repository/playground/}"
  export REPOSITORY_ID="${REPOSITORY_ID:-osera-playground}"
  export OSERA_SKIP_SIGN="${OSERA_SKIP_SIGN:-1}"
}

skip_sign_by_default() {
  case "${OSERA_SKIP_SIGN:-1}" in
    1|true|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
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
