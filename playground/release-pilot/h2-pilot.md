# H2 pilot walkthrough

[`finos-osera/backpatch-h2`](https://github.com/finos-osera/backpatch-h2) tag `v1.4.200+backpatch.001` → **`playground`** Nexus repo.

```bash
PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-h2
```

Target: [https://finos-osera.repo.sonatype.app/repository/playground/](https://finos-osera.repo.sonatype.app/repository/playground/)  
Signing: **skipped** by default (`OSERA_SKIP_SIGN=1`). See [signing-setup.md](signing-setup.md) to enable.

---

## 1. Configure Maven

Copy [`templates/settings.xml.template`](templates/settings.xml.template) to `~/.m2/settings.xml`. Set server id **`osera-playground`** and Nexus deploy credentials.

## 2. Build

Requires **JDK 17** (auto-selected). JDK 23 is overridden — the h2 POM targets Java 7 and only JDK 17 can compile it via Maven. `./build.sh compile` is skipped (breaks on JDK 9+).

```bash
eval "$($PILOT/scripts/release/build-h2.sh)"
```

If detection fails:

```bash
brew install openjdk@17   # macOS
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
eval "$($PILOT/scripts/release/build-h2.sh)"
```

## 3. Publish (unsigned by default)

`publish-staging.sh` generates the release manifest from git (`baseline..tag` commits) automatically:

```bash
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging "$STAGING" \
  --module-dir "$module_dir" \
  --jar "$jar" \
  --pom "$pom"
```

Manifest and sidecars land under `/tmp/osera-releases/h2/`. To inspect or regenerate standalone, use [`generate-release-manifest.sh`](scripts/release/generate-release-manifest.sh).

How the manifest is filled from git (`scripts/lib/generate_release_manifest.sh`):

| Manifest field | Source |
| -------------- | ------ |
| `coordinate.version` | Publish tag with leading `v` stripped (`v1.4.200+backpatch.001` → `1.4.200+backpatch.001`) |
| `coordinate.groupId` / `artifactId` | CLI args (`--group-id`, `--artifact-id`) |
| `tag` | `--tag` (publish tag) |
| `baselineTag` | `--baseline-tag`, or derived as `v{upstream}+backpatch.baseline` from the publish tag |
| `provenance.oseraCommit` | Last commit on `baselineTag..tag`; URL built from `origin` (org/repo) + that SHA |
| `provenance.upstreamUrl` | `owner/repo@sha` (optional `Reference:` prefix) in any commit message in the range |
| `vulnerabilities[].id` | Unique `CVE-YYYY-NNNN…` strings grepped from all commit bodies in the range |
| `vulnerabilities[].action` | Generated from those CVEs + baseline tag (or a generic sentence if none) |
| `patchBasis` | `provider-developed` if any message matches that phrase; else `upstream-backport` |
| `recipientGuidance.whatChanged` | Subject (+ first non-empty body line) of the last commit in the range |
| `recipientGuidance.suggestedTestSurface` | Heuristics on commit text (`*Test` class names, “web console”, JDBC/JNDI, “embedded”); fallback smoke-test line |

Commit range is `git rev-list --reverse baselineTag..tag`. Output defaults to `/tmp/osera-releases/{repo-without-backpatch-prefix}/{version}.yaml` (h2 → `/tmp/osera-releases/h2/…`).

Or step by step (after generating manifest):

```bash
MANIFEST=/tmp/osera-releases/h2/1.4.200+backpatch.001.yaml
$PILOT/scripts/release/generate-openvex.sh --manifest "$MANIFEST"
$PILOT/scripts/release/generate-sbom.sh --mode maven --module-dir "$module_dir" --output /tmp/h2-cyclonedx.json
$PILOT/scripts/publish/stage-artifacts.sh \
  --manifest "$MANIFEST" --staging "$STAGING" \
  --jar "$jar" --pom "$pom" --sbom /tmp/h2-cyclonedx.json
$PILOT/scripts/publish/publish-to-nexus.sh --manifest "$MANIFEST" --staging "$STAGING"
$PILOT/scripts/publish/verify-publish.sh --manifest "$MANIFEST" --staging "$STAGING"
```

## 4. Confirm in Nexus

Browse: [playground / com/h2database/h2/1.4.200+backpatch.001](https://finos-osera.repo.sonatype.app/#browse/browse:playground:com%2Fh2database%2Fh2%2F1.4.200%2Bbackpatch.001)

---

## Optional: signed publish

```bash
$PILOT/scripts/sign/generate-finos-key.sh
source $PILOT/signing/local.env
$PILOT/scripts/sign/generate-vendor-key.sh --vendor-slug acme
source $PILOT/signing/local.env

export OSERA_SKIP_SIGN=0
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging "$STAGING" \
  --module-dir "$module_dir" --jar "$jar" --pom "$pom" \
  --sign
```

Details: [signing-setup.md](signing-setup.md) · proposal: [../backpatch-signing.md](../backpatch-signing.md).

---

*Deploy defaults: [nexus-playground.md](nexus-playground.md)*
