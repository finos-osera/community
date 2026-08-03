# Spring Framework pilot walkthrough

[`finos-osera/backpatch-spring-framework`](https://github.com/finos-osera/backpatch-spring-framework) tag `v5.3.39+backpatch.001` → **`playground`** Nexus repo.

Publishes **all** `spring-*` modules plus `spring-framework-bom` (`org.springframework:*:5.3.39+backpatch.001`).

```bash
PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-spring
```

Target: [https://finos-osera.repo.sonatype.app/repository/playground/](https://finos-osera.repo.sonatype.app/repository/playground/)  
Signing: **skipped** by default (`OSERA_SKIP_SIGN=1`). See [signing-setup.md](signing-setup.md) to enable.

---

## 1. Configure Maven

Same as h2: copy [`templates/settings.xml.template`](templates/settings.xml.template) to `~/.m2/settings.xml`. Server id **`osera-playground`**.

Deploy still uses `mvn deploy:deploy-file` (Gradle only builds).

## 2. Build (Gradle)

Requires **JDK 8, 11, or 17** (8 preferred per `.sdkmanrc`; auto-selected). Spring 5.3.x compiles at source 8. On JDK 11/17, `build-spring.sh` applies [`templates/spring-jdk-compat.init.gradle`](templates/spring-jdk-compat.init.gradle) so `-Werror` does not fail on `java.security` `[removal]` warnings.

```bash
eval "$($PILOT/scripts/release/build-spring.sh)"
```

Exports: `repo_dir`, `tag`, `group_id`, `version`, `modules_file` (TSV of every module’s jar/pom).

Optional allowlist (comma-separated module dir names):

```bash
eval "$($PILOT/scripts/release/build-spring.sh --modules spring-webmvc,spring-webflux,framework-bom)"
```

First run clones into `/tmp/backpatch-spring-framework-build` and may take several minutes (Gradle + deps).

If JDK detection fails:

```bash
brew install openjdk@17
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
eval "$($PILOT/scripts/release/build-spring.sh)"
```

## 3. Publish (unsigned by default)

```bash
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging "$STAGING"
```

Per module this generates a manifest under `/tmp/osera-releases/spring-framework/{artifactId}/`, builds OpenVEX + CycloneDX, stages, deploys, and verifies.

Dry run (stage + verify local only):

```bash
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging "$STAGING" \
  --dry-run
```

### Gradle-specific notes

| Topic | Behavior |
| ----- | -------- |
| Version | `-Pversion=5.3.39+backpatch.001` overrides `gradle.properties` (`version=5.3.39`) |
| POMs | `generatePomFileForMavenJavaPublication` (maven-publish); no fork edits |
| JDK 11/17 | [`spring-jdk-compat.init.gradle`](templates/spring-jdk-compat.init.gradle) drops `-Werror` / silences `-removal` (fork keeps `-Werror` for JDK 8) |
| SBOM | CycloneDX via [`templates/cyclonedx-gradle.init.gradle`](templates/cyclonedx-gradle.init.gradle); falls back to a coordinate-only SBOM |
| BOM | `framework-bom` → `spring-framework-bom` packaging `pom` (no JAR) |
| Tests | Skipped (`-x test -x check`), same spirit as h2’s `-Dmaven.test.skip` |

## 4. Confirm in Nexus

Browse e.g. [playground / org/springframework/spring-webmvc/5.3.39+backpatch.001](https://finos-osera.repo.sonatype.app/#browse/browse:playground:org%2Fspringframework%2Fspring-webmvc%2F5.3.39%2Bbackpatch.001)

Resolve one module:

```bash
mvn dependency:get \
  -DremoteRepositories=osera-playground::::https://finos-osera.repo.sonatype.app/repository/playground/ \
  -Dartifact=org.springframework:spring-webmvc:5.3.39+backpatch.001 \
  -Dtransitive=false
```

---

## Optional: signed publish

```bash
export OSERA_SKIP_SIGN=0
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging "$STAGING" \
  --sign
```

Details: [signing-setup.md](signing-setup.md).

---

*CVE-2024-38816 in this tag patches `spring-webmvc` / `spring-webflux`; the pilot still publishes the full module set so the line stays BOM-consistent.*
