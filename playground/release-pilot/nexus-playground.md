# Playground Nexus publish test

First live publish target for release-pilot: the `playground` hosted repository on Sonatype Nexus.

**Deploy URL:** [https://finos-osera.repo.sonatype.app/repository/playground/](https://finos-osera.repo.sonatype.app/repository/playground/)  
**Browse UI:** [finos-osera.repo.sonatype.app → playground](https://finos-osera.repo.sonatype.app/#browse/browse:playground)  
**Maven** `repositoryId`**:** `osera-playground` (must match `~/.m2/settings.xml`)

Defaults live in [`config/nexus-playground.env`](config/nexus-playground.env). Scripts load this automatically.

---

## Prerequisites

1. **Nexus credentials** — deploy user/token with write access to `playground`.
2. `~/.m2/settings.xml` — copy from [`templates/settings.xml.template`](templates/settings.xml.template); set `<id>osera-playground</id>` and credentials.
3. **Tooling** — `java`, `mvn`, `git`, `jq` (optional: `yq` or `python3`+PyYAML for manifest YAML; `cyclonedx` CLI for SBOM validation; `gpg` when signing). Spring builds use the repo’s `./gradlew` (no system Gradle required).

**Signing:** skipped by default (`OSERA_SKIP_SIGN=1`). To exercise signatures, see [signing-setup.md](signing-setup.md).

---

## Publish test (h2 pilot)

From repo root:

```bash
PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-h2

eval "$($PILOT/scripts/release/build-h2.sh)"
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging "$STAGING" \
  --module-dir "$module_dir" --jar "$jar" --pom "$pom"
```

## Publish test (Spring Framework pilot)

Publishes all `org.springframework:spring-*` modules plus `spring-framework-bom` for tag `v5.3.39+backpatch.001`:

```bash
PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-spring

eval "$($PILOT/scripts/release/build-spring.sh)"
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging "$STAGING"
```

Dry run (no upload):

```bash
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging "$STAGING" \
  --module-dir "$module_dir" --jar "$jar" --pom "$pom" \
  --dry-run
```

Deploy only (after staging; manifest at `/tmp/osera-releases/h2/1.4.200+backpatch.001.yaml`):

```bash
MANIFEST=/tmp/osera-releases/h2/1.4.200+backpatch.001.yaml
$PILOT/scripts/publish/publish-to-nexus.sh --manifest "$MANIFEST" --staging "$STAGING"
$PILOT/scripts/publish/verify-publish.sh --manifest "$MANIFEST" --staging "$STAGING"
```

---

## Expected coordinate

After a successful **h2** publish:


| Field      | Value                                                          |
| ---------- | -------------------------------------------------------------- |
| GAV        | `com.h2database:h2:1.4.200+backpatch.001`                      |
| Sidecars   | `-cyclonedx.json`, `.openvex.json`, `-recipient-guidance.yaml` |
| Signatures | none unless `OSERA_SKIP_SIGN=0` / `--sign`                     |


After a successful **Spring** publish: one GAV per module under `org.springframework` at `5.3.39+backpatch.001` (e.g. `spring-webmvc`, `spring-framework-bom`).

Resolve check (h2):

```bash
mvn dependency:get \
  -DremoteRepositories=osera-playground::::https://finos-osera.repo.sonatype.app/repository/playground/ \
  -Dartifact=com.h2database:h2:1.4.200+backpatch.001 \
  -Dtransitive=false
```

---

## 409 Conflict (redeploy blocked)

The `playground` repo rejects overwriting an existing GAV ([REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/)). A **409** usually means a prior partial publish left artifacts at `com/h2database/h2/1.4.200+backpatch.001/`.

**Fix:** in Nexus UI, delete the **entire version folder** (not just individual files), then re-run publish. Or bump `+backpatch.NNN` in the manifest/tag.

The publish script deploys **JAR + POM once** (`-DpomFile` + `-DgeneratePom=false`), or **POM-only** for BOMs (`--packaging pom`). Sidecars use `-DgeneratePom=false` so Maven does not attempt a second POM upload. OpenPGP files are uploaded as **siblings** (`*.jar.asc`, `*.jar.asc.finos`) via HTTP PUT — not as Maven classifiers (`*-vendor.asc`), which Nexus rejects (`Invalid mavenPath`).

---

## Overrides

```bash
export NEXUS_URL=https://finos-osera.repo.sonatype.app/repository/playground/
export REPOSITORY_ID=osera-playground
export OSERA_SKIP_SIGN=1
```

Step-by-step: [h2-pilot.md](h2-pilot.md) · [spring-pilot.md](spring-pilot.md)

---

*2026-08-03 — Spring Gradle multi-module publish path.*
