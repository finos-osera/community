#!/usr/bin/env bash
# Generate release manifest YAML from git tags/commits (baseline..publish).
# shellcheck shell=bash

generate_release_manifest() {
  local repo_dir="$1" tag="$2" group_id="$3" artifact_id="$4"
  local baseline_tag="${5:-}" github_org="${6:-}" output_path="${7:-}"

  local version="${tag#v}" remote github_repo short_name
  local commit_range primary_sha primary_body primary_subject all_text
  local patch_basis upstream_url action osera_commit
  local -a commit_shas cves what_changed test_surface sha cve

  if [[ -z "$baseline_tag" ]]; then
    if [[ "$version" =~ ^(.+\+)backpatch\.[0-9]+$ ]]; then
      baseline_tag="v${BASH_REMATCH[1]}backpatch.baseline"
    else
      echo "error: could not derive baseline tag from ${tag}" >&2
      return 1
    fi
  fi

  github_repo="$(basename "$repo_dir")"
  if remote="$(git -C "$repo_dir" remote get-url origin 2>/dev/null)"; then
    remote="${remote//$'\n'/}"
    remote="${remote//$'\r'/}"
    if [[ "$remote" =~ github\.com[:/]+([^/]+)/([^/.]+)(\.git)?$ ]]; then
      github_org="${github_org:-${BASH_REMATCH[1]}}"
      github_repo="${BASH_REMATCH[2]}"
    fi
  fi
  github_org="${github_org:-finos-osera}"

  commit_shas=()
  while IFS= read -r sha; do
    [[ -n "$sha" ]] && commit_shas+=("$sha")
  done < <(git -C "$repo_dir" rev-list --reverse "${baseline_tag}..${tag}" 2>/dev/null || true)
  if [[ ${#commit_shas[@]} -eq 0 ]]; then
    echo "error: no commits between ${baseline_tag} and ${tag}" >&2
    return 1
  fi

  all_text=""
  for sha in "${commit_shas[@]}"; do
    all_text+=$(git -C "$repo_dir" log -1 --format=%B "$sha")
    all_text+=$'\n'
  done

  primary_sha="${commit_shas[${#commit_shas[@]}-1]}"
  primary_body="$(git -C "$repo_dir" log -1 --format=%B "$primary_sha")"
  primary_subject="${primary_body%%$'\n'*}"

  cves=()
  while IFS= read -r cve; do
    [[ -n "$cve" ]] && cves+=("$cve")
  done < <(grep -oE 'CVE-[0-9]{4}-[0-9]+' <<< "$all_text" | sort -u)

  if grep -qi 'provider[- ]developed' <<< "$all_text"; then
    patch_basis="provider-developed"
  else
    patch_basis="upstream-backport"
  fi

  if [[ "$all_text" =~ Reference:[[:space:]]*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{7,40}) ]]; then
    upstream_url="https://github.com/${BASH_REMATCH[1]}/commit/${BASH_REMATCH[2]}"
  elif [[ "$all_text" =~ ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{7,40}) ]]; then
    upstream_url="https://github.com/${BASH_REMATCH[1]}/commit/${BASH_REMATCH[2]}"
  else
    upstream_url=""
  fi

  osera_commit="https://github.com/${github_org}/${github_repo}/commit/${primary_sha}"

  if [[ ${#cves[@]} -gt 0 ]]; then
    local cve_list
    cve_list="$(IFS=', '; echo "${cves[*]}")"
    action="Fixed ${cve_list} by backporting upstream remediation onto baseline ${baseline_tag#v}."
  else
    action="Security fix applied on baseline ${baseline_tag#v} per OSERA backpatch commit ${primary_sha:0:7}."
  fi

  what_changed=("$primary_subject")
  local summary_line=""
  summary_line="$(awk 'NR>1 { gsub(/^[ \t]+|[ \t]+$/, ""); if (length($0)) { print; exit } }' <<< "$primary_body")"
  if [[ -n "$summary_line" ]]; then
    what_changed+=("$summary_line")
  fi

  test_surface=()
  local test_class
  while IFS= read -r test_class; do
    [[ -n "$test_class" ]] && test_surface+=("Run ${test_class}")
  done < <(grep -oE 'org\.[A-Za-z0-9_.]+\.[A-Za-z0-9_]+Test' <<< "$all_text" | sort -u)

  if grep -qi 'web console' <<< "$all_text"; then
    test_surface+=("H2 web console login form")
  fi
  if grep -qE 'JdbcUtils|JDBC' <<< "$all_text"; then
    test_surface+=("JDBC connectivity and JNDI datasource paths (java: scheme)")
  fi
  if grep -qi 'embedded' <<< "$all_text"; then
    test_surface+=("Embedded mode startup")
  fi
  if [[ ${#test_surface[@]} -eq 0 ]]; then
    test_surface=("Smoke-test patched library startup and primary integration paths")
  fi

  if [[ -z "$output_path" ]]; then
    short_name="${github_repo#backpatch-}"
    output_path="/tmp/osera-releases/${short_name}/${version}.yaml"
  fi
  mkdir -p "$(dirname "$output_path")"

  local vulns_json what_changed_json test_surface_json manifest_json
  vulns_json='[]'
  for cve in "${cves[@]}"; do
    vulns_json="$(jq -cn \
      --argjson arr "$vulns_json" \
      --arg id "$cve" \
      --arg action "$action" \
      '$arr + [{id: $id, status: "fixed", action: $action}]')"
  done

  what_changed_json="$(printf '%s\n' "${what_changed[@]}" | jq -R . | jq -s .)"
  test_surface_json="$(printf '%s\n' "${test_surface[@]}" | jq -R . | jq -s .)"

  manifest_json="$(jq -cn \
    --arg groupId "$group_id" \
    --arg artifactId "$artifact_id" \
    --arg version "$version" \
    --arg tag "$tag" \
    --arg baselineTag "$baseline_tag" \
    --arg patchBasis "$patch_basis" \
    --arg upstreamUrl "$upstream_url" \
    --arg oseraCommit "$osera_commit" \
    --argjson vulnerabilities "$vulns_json" \
    --argjson whatChanged "$what_changed_json" \
    --argjson suggestedTestSurface "$test_surface_json" \
    '{
      coordinate: { groupId: $groupId, artifactId: $artifactId, version: $version },
      tag: $tag,
      baselineTag: $baselineTag,
      patchBasis: $patchBasis,
      provenance: (
        { upstreamUrl: $upstreamUrl, oseraCommit: $oseraCommit }
        | with_entries(select(.value != ""))
      ),
      vulnerabilities: $vulnerabilities,
      recipientGuidance: {
        whatChanged: $whatChanged,
        suggestedTestSurface: $suggestedTestSurface
      }
    }')"

  json_to_yaml <<< "$manifest_json" > "$output_path"
  printf '%s\n' "$output_path"
}
