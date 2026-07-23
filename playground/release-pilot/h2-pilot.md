# H2 pilot walkthrough

[`finos-osera/backpatch-h2`](https://github.com/finos-osera/backpatch-h2) tag `v1.4.200+backpatch.001` → **`playground`** Nexus repo.

```bash
PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-h2
```

Target: [https://finos-osera.repo.sonatype.app/repository/playground/](https://finos-osera.repo.sonatype.app/repository/playground/)  
Signing: **skipped** for this test (`OSERA_SKIP_SIGN=1`).

---

## 1. Configure Maven

Copy [`templates/settings.xml.template`](templates/settings.xml.template) to `~/.m2/settings.xml`. Set server id **`osera-playground`** and Nexus deploy credentials.

## 2. Build

Requires **JDK 17** (auto-selected). JDK 23 is overridden — the h2 POM targets Java 7 and only JDK 17 can compile it via Maven. `./build.sh compile` is skipped (breaks on JDK 9+).

```bash
eval "$($PILOT/scripts/build-h2.sh)"
```

If detection fails:

```bash
brew install openjdk@17   # macOS
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
eval "$($PILOT/scripts/build-h2.sh)"
```

## 3. Publish (unsigned)

`publish-staging.sh` generates the release manifest from git (`baseline..tag` commits) automatically:

```bash
$PILOT/scripts/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging "$STAGING" \
  --module-dir "$module_dir" \
  --jar "$jar" \
  --pom "$pom"
```

Manifest and sidecars land under `/tmp/osera-releases/h2/`. To inspect or regenerate standalone, use [`generate-release-manifest.sh`](scripts/generate-release-manifest.sh).

Or step by step (after generating manifest):

```bash
MANIFEST=/tmp/osera-releases/h2/1.4.200+backpatch.001.yaml
$PILOT/scripts/generate-openvex.sh --manifest "$MANIFEST"
$PILOT/scripts/generate-sbom.sh --mode maven --module-dir "$module_dir" --output /tmp/h2-cyclonedx.json
$PILOT/scripts/stage-artifacts.sh \
  --manifest "$MANIFEST" --staging "$STAGING" \
  --jar "$jar" --pom "$pom" --sbom /tmp/h2-cyclonedx.json
$PILOT/scripts/publish-to-nexus.sh --manifest "$MANIFEST" --staging "$STAGING"
$PILOT/scripts/verify-publish.sh --manifest "$MANIFEST" --staging "$STAGING"
```

## 4. Confirm in Nexus

Browse: [playground / com/h2database/h2/1.4.200+backpatch.001](https://finos-osera.repo.sonatype.app/#browse/browse:playground:com%2Fh2database%2Fh2%2F1.4.200%2Bbackpatch.001)

---

## Later: signing

When keys are provisioned, set `OSERA_SKIP_SIGN=0` in config (or export it) and re-run with `--sign`. See [../backpatch-signing.md](../backpatch-signing.md).

---

*Deploy defaults: [nexus-playground.md](nexus-playground.md)*
