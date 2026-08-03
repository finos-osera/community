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

End-to-end orchestrators: `release-pilot/scripts/publish/publish-staging.sh` (h2) and `publish-spring-staging.sh` (Spring). Deploy defaults: [`release-pilot/config/nexus-playground.env`](release-pilot/config/nexus-playground.env).

---

## Standards — pilot implementation

### [REL-001](https://standards.osera.finos.org/standards/rel-001-build-process/) Provider Build Process

**Status: partially implemented** (h2 + Spring pilots).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Reproducible build from publish tag | `build-h2.sh` / `build-spring.sh` clone the fork, check out `v<UPSTREAM>+backpatch.NNN`, build with Maven or Gradle |
| Toolchain outside fork | All scripts live in `playground/release-pilot/` — no edits to backpatch repos |
| Build JDK | `ensure_h2_java_home` forces JDK **17**; `ensure_spring_java_home` prefers **17** (8/11 also OK for Spring 5.3.x source 8) |
| Evidence / audit log | Not implemented — no `publish-log.yaml` or CI attestations yet |

**Why partial:** only h2 and Spring have build scripts. Other repos will need per-repo builders before fleet rollout.

---

### [REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) Bytecode Compatibility

**Status: stub only.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Patched JAR matches baseline bytecode level | `check-bytecode.sh` compares **major class-file version** of one sample `.class` via `javap` |
| Baseline JAR input | Optional `--baseline-jar`; **not passed** in default publish flows — script logs major version and warns |
| Fail on mismatch | Only when `--baseline-jar` is supplied |
| POM-only artifacts | Skipped for `spring-framework-bom` |

**Why stub:** REL-002 needs a baseline artifact per coordinate (typically built from the `.baseline` tag). The pilot has not wired baseline JAR extraction or enforcement yet.

---

### [REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) Backpatch Version Metadata

**Status: implemented.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| Version format `<UPSTREAM>+backpatch.NNN` | Publish tag → Maven coordinate in generated manifest; Spring overrides Gradle `version` via `-Pversion=` |
| Immutable coordinates | Nexus `playground` repo rejects redeploy (**409**); fix by deleting the version folder or bumping `+backpatch.NNN` — see [nexus-playground.md](release-pilot/nexus-playground.md) |
| Provenance in manifest | `generate-release-manifest.sh` writes `tag`, `baselineTag`, `provenance.upstreamUrl`, `provenance.oseraCommit` from git commits between tags |
| Multi-module | Spring: one manifest + GAV per `spring-*` module and `spring-framework-bom` |
| Sidecar naming | `{artifactId}-{version}.*` per [artifact-layout.md](release-pilot/artifact-layout.md); deployed via `publish-to-nexus.sh` with Maven classifiers |

---

### [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) OpenVEX and CycloneDX Feeds

**Status: implemented** (unsigned playground publish).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| CycloneDX SBOM | `generate-sbom.sh --mode maven` (h2) or `--mode gradle` / `--mode coordinate` (Spring) |
| OpenVEX | `generate-openvex.sh` builds `.openvex.json` from manifest `vulnerabilities[]` (CVE + `fixed` status + action statement) |
| Post-publish checks | `verify-publish.sh` validates SBOM bom-ref vs expected PURL, prints OpenVEX statements, optionally runs `cyclonedx validate` |

**Why implemented:** both sidecars are generated, staged, deployed, and checked in the default pipeline. SBOM bom-ref may still show the fork's internal version while the published coordinate uses `+backpatch.NNN` — a known gap to align later. Spring may fall back to a coordinate-only SBOM if the Gradle CycloneDX init script does not emit a report.

---

### [FORK-003](https://standards.osera.finos.org/standards/fork-003-baseline-tags/) Baseline Tags

**Status: implemented** (metadata only; baseline artifact not built).

| Requirement | Pilot behavior |
| ----------- | -------------- |
| `.baseline` tag marks fork point | Manifest generator derives `baselineTag` as `v{UPSTREAM}+backpatch.baseline` from the publish tag |
| Only publish tags released | Build and deploy use `v…+backpatch.NNN`, not the baseline tag |
| Patch scope from git | `git rev-list baselineTag..publishTag` — manifest CVE/provenance/recipient fields come from those commits |

---

### [EVD-001](https://standards.osera.finos.org/standards/evd-001-change-and-test-surface/) Change and Test Surface

**Status: partially implemented.**

| Requirement | Pilot behavior |
| ----------- | -------------- |
| What changed | `recipientGuidance.whatChanged` from backpatch commit subject + summary line (`lib/generate_release_manifest.sh`) |
| Suggested test surface | Heuristics on commit message: `*Test` class names, H2 strings, Spring path-traversal / web-module hints; fallback smoke-test line |
| Published sidecar | `generate-openvex.sh` writes `{version}.recipient-guidance.yaml`; staged and deployed with classifier `recipient-guidance` |

---

### Signing (proposed — not in OSERA catalog)

**Status: implemented in pilot, off by default.** Vendor OpenPGP + FINOS co-sign: [backpatch-signing.md](backpatch-signing.md). Ops + keygen: [release-pilot/signing-setup.md](release-pilot/signing-setup.md). `OSERA_SKIP_SIGN=1` skips sign/deploy/verify signature checks unless `--sign` / `OSERA_SKIP_SIGN=0`.

---

## Current test target

| Setting | Value |
| ------- | ----- |
| URL | `https://finos-osera.repo.sonatype.app/repository/playground/` |
| Maven server id | `osera-playground` |
| Signatures | Skipped by default (`OSERA_SKIP_SIGN=1`) |

---

## Pilot docs

- [Playground publish test](release-pilot/nexus-playground.md)
- [Signing setup](release-pilot/signing-setup.md)
- [H2 walkthrough](release-pilot/h2-pilot.md)
- [Spring walkthrough](release-pilot/spring-pilot.md)
- [Artifact layout](release-pilot/artifact-layout.md)

---

*2026-08-03 — Spring Gradle multi-module pilot mapped alongside h2.*
