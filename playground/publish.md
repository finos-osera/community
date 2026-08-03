# OSERA Artifact Publishing

How backpatch releases reach the consortium Nexus hub: build evidence, supply-chain metadata, and immutable coordinates.

**Registry:** [finos-osera.repo.sonatype.app](https://finos-osera.repo.sonatype.app/)  
**Playground test repo:** […/repository/playground/](https://finos-osera.repo.sonatype.app/repository/playground/)  
**Production (planned):** `https://repo.osera.finos.org/`  
**Standards:** [OSERA Patching Standards](https://standards.osera.finos.org/)

---

## What gets published

Tag-driven releases: `v<UPSTREAM>+backpatch.NNN` ([REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/)). `.baseline` tags are not published ([FORK-003](https://standards.osera.finos.org/standards/fork-003-baseline-tags/)).

Each coordinate includes JAR, POM, CycloneDX SBOM, and OpenVEX ([FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/)). Signing is optional in playground (`OSERA_SKIP_SIGN=1` by default); proposal: [backpatch-signing.md](backpatch-signing.md); ops: [release-pilot/signing-setup.md](release-pilot/signing-setup.md).

Tooling: [release-pilot/](release-pilot/README.md) (outside `finos-osera/backpatch-*` forks).

---

## Guides

| Topic | Document |
| ----- | -------- |
| Principles (REL, FEED) | [release-process.md](release-process.md) |
| **Playground publish test** | [release-pilot/nexus-playground.md](release-pilot/nexus-playground.md) |
| Pilot scripts | [release-pilot/README.md](release-pilot/README.md) |
| Signing (proposal) | [backpatch-signing.md](backpatch-signing.md) |
| Signing (ops) | [release-pilot/signing-setup.md](release-pilot/signing-setup.md) |
| Infrastructure | [infra-setup.md](infra-setup.md) · [infra-budget.md](infra-budget.md) |

---

## Quick start — playground publish

Configure `~/.m2/settings.xml` from [release-pilot/templates/settings.xml.template](release-pilot/templates/settings.xml.template) (`osera-playground` server id), then:

**H2:**

```bash
PILOT=playground/release-pilot
eval "$($PILOT/scripts/release/build-h2.sh)"
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging /tmp/osera-staging-h2 \
  --module-dir "$module_dir" --jar "$jar" --pom "$pom"
```

**Spring Framework** (all `spring-*` + BOM):

```bash
PILOT=playground/release-pilot
eval "$($PILOT/scripts/release/build-spring.sh)"
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging /tmp/osera-staging-spring
```

Full checklist: [release-pilot/nexus-playground.md](release-pilot/nexus-playground.md) · [release-pilot/spring-pilot.md](release-pilot/spring-pilot.md)

---

*2026-08-03 — Spring Gradle multi-module pilot.*
