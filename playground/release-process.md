# OSERA Release Process & Supply-Chain Feeds

Operator playbook for building, documenting, and publishing backpatch releases. Runnable tooling: [release-pilot/README.md](release-pilot/README.md). Live test target: [release-pilot/nexus-playground.md](release-pilot/nexus-playground.md).

| ID | Standard | Link |
| -- | -------- | ---- |
| REL-001 | Provider Build Process | [rel-001](https://standards.osera.finos.org/standards/rel-001-build-process/) |
| REL-002 | Bytecode Compatibility | [rel-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) |
| REL-003 | Backpatch Version Metadata | [rel-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) |
| FEED-001 | OpenVEX and CycloneDX Feeds | [feed-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) |
| FORK-003 | Baseline Tags | [fork-003](https://standards.osera.finos.org/standards/fork-003-baseline-tags/) |
| EVD-001 | Change and Test Surface | [evd-001](https://standards.osera.finos.org/standards/evd-001-change-and-test-surface/) |

End-to-end orchestrator: `release-pilot/scripts/publish-staging.sh` (after `build-h2.sh` for the h2 pilot). Deploy defaults: [`release-pilot/config/nexus-playground.env`](release-pilot/config/nexus-playground.env).

---

## Standards — pilot implementation

### [REL-001](https://standards.osera.finos.org/standards/rel-001-build-process/) Provider Build Process

**Status: partially implemented** (h2 pilot only).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Reproducible build from publish tag | `build-h2.sh` clones `finos-osera/backpatch-h2`, checks out `v<UPSTREAM>+backpatch.NNN`, runs `mvn clean package -Dmaven.test.skip=true` |
| Toolchain outside fork | All scripts live in `playground/release-pilot/` — no edits to backpatch repos |
| Build JDK | `ensure_h2_java_home` in `lib/common.sh` forces JDK **17** (h2 POM targets Java 7; JDK 21+ fails). Path is auto-detected via `/usr/libexec/java_home -v 17` or Homebrew `openjdk@17` |
| Evidence / audit log | Not implemented — no `publish-log.yaml` or CI attestations yet |

**Why partial:** only `backpatch-h2` has a build script (`build-h2.sh`). Other repos will need per-repo builders before fleet rollout.

---

### [REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) Bytecode Compatibility

**Status: stub only.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Patched JAR matches baseline bytecode level | `check-bytecode.sh` compares **major class-file version** of one sample `.class` via `javap` |
| Baseline JAR input | Optional `--baseline-jar`; **not passed** in default `publish-staging.sh` flow — script logs major version and warns |
| Fail on mismatch | Only when `--baseline-jar` is supplied |

**Why stub:** REL-002 needs a baseline artifact per coordinate (typically built from the `.baseline` tag). The pilot has not wired baseline JAR extraction or enforcement yet. JDK 17 selection in REL-001 is an indirect guard for h2, not a generic REL-002 implementation.

---

### [REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) Backpatch Version Metadata

**Status: implemented.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Version format `<UPSTREAM>+backpatch.NNN` | Publish tag `v1.4.200+backpatch.001` → Maven coordinate `com.h2database:h2:1.4.200+backpatch.001` in generated manifest |
| Immutable coordinates | Nexus `playground` repo rejects redeploy (**409**); fix by deleting the version folder or bumping `+backpatch.NNN` — see [nexus-playground.md](release-pilot/nexus-playground.md) |
| Provenance in manifest | `generate-release-manifest.sh` writes `tag`, `baselineTag`, `provenance.upstreamUrl`, `provenance.oseraCommit` from git commits between tags |
| Sidecar naming | `{artifactId}-{version}.*` per [artifact-layout.md](release-pilot/artifact-layout.md); deployed via `publish-to-nexus.sh` with Maven classifiers |

**Why implemented:** tag → manifest → GAV → staged filenames → Nexus path is fully scripted and verified with `mvn dependency:get` in `verify-publish.sh`.

---

### [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) OpenVEX and CycloneDX Feeds

**Status: implemented** (unsigned playground publish).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| CycloneDX SBOM | `generate-sbom.sh --mode maven` runs CycloneDX Maven plugin on the built module; output staged as `{artifactId}-{version}-cyclonedx.json` |
| OpenVEX | `generate-openvex.sh` builds `.openvex.json` from manifest `vulnerabilities[]` (CVE + `fixed` status + action statement) |
| Post-publish checks | `verify-publish.sh` validates SBOM bom-ref vs expected PURL, prints OpenVEX statements, optionally runs `cyclonedx validate` |

**Why implemented:** both sidecars are generated, staged, deployed, and checked in the default pipeline. SBOM bom-ref may still show the fork's internal Maven version (e.g. `1.4.201-SNAPSHOT`) while the published coordinate uses `+backpatch.NNN` — a known gap to align later.

---

### [FORK-003](https://standards.osera.finos.org/standards/fork-003-baseline-tags/) Baseline Tags

**Status: implemented** (metadata only; baseline artifact not built).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| `.baseline` tag marks fork point | Manifest generator derives `baselineTag` as `v{UPSTREAM}+backpatch.baseline` from the publish tag |
| Only publish tags released | Build and deploy use `v1.4.200+backpatch.001`, not the baseline tag |
| Patch scope from git | `git rev-list baselineTag..publishTag` — manifest CVE/provenance/recipient fields come from those commits |

**Why implemented:** baseline tag is referenced in every generated manifest and scopes what changed; the baseline **binary** is not yet produced for REL-002 comparison.

---

### [EVD-001](https://standards.osera.finos.org/standards/evd-001-change-and-test-surface/) Change and Test Surface

**Status: partially implemented.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| What changed | `recipientGuidance.whatChanged` from backpatch commit subject + summary line (`lib/generate_release_manifest.sh`) |
| Suggested test surface | Heuristics on commit message: `*Test` class names, H2-specific strings (web console, JDBC/JNDI, embedded); fallback smoke-test line |
| Published sidecar | `generate-openvex.sh` writes `{version}.recipient-guidance.yaml`; staged and deployed with classifier `recipient-guidance` |

**Why partial:** fields are inferred from commit messages, not from a structured EVD block in the repo. Manual manifest edit is possible but discouraged — regenerate from git when commits are well-formed.

---

### Signing (proposed — not in OSERA catalog)

**Status: deferred.** Vendor GPG + FINOS co-sign: [backpatch-signing.md](backpatch-signing.md). Scripts exist (`vendor-sign.sh`, `finos-cosign.sh`) but `OSERA_SKIP_SIGN=1` skips them in playground.

---

## Current test target

| Setting | Value |
| ------- | ----- |
| URL | `https://finos-osera.repo.sonatype.app/repository/playground/` |
| Maven server id | `osera-playground` |
| Signatures | Skipped (`OSERA_SKIP_SIGN=1`) |

---

## Pilot docs

- [Playground publish test](release-pilot/nexus-playground.md)
- [H2 walkthrough](release-pilot/h2-pilot.md)
- [Artifact layout](release-pilot/artifact-layout.md)

---

*2026-07-23 — standards mapped to release-pilot; h2 playground publish validated.*
