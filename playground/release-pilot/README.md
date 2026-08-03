# Release pilot

Runnable operator toolkit for the `backpatch-h2` and `backpatch-spring-framework` pilots and fleet rollout. Scripts live under `scripts/{release,publish,sign}/`; release manifests are generated from git tags (not checked in).

**Standards:** [REL-001](https://standards.osera.finos.org/standards/rel-001-build-process/) · [REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) · [REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) · [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/)

**Related:** [nexus-playground.md](nexus-playground.md) · [signing-setup.md](signing-setup.md) · [../release-process.md](../release-process.md) · [../publish.md](../publish.md) · [../backpatch-signing.md](../backpatch-signing.md)

---

## Status


| Item               | Status                                                                                                                               |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Pilot scripts      | **Ready** (h2 Maven + Spring Gradle)                                                                                                 |
| Nexus test target  | `playground` repo — [nexus-playground.md](nexus-playground.md)                                                                       |
| Pilot manifest     | Generated from git by publish scripts (or [`release/generate-release-manifest.sh`](scripts/release/generate-release-manifest.sh)) |
| Artifact signing   | **Skipped by default** — `OSERA_SKIP_SIGN=1`; enable via [signing-setup.md](signing-setup.md)                                        |
| Production signing | Proposed — [../backpatch-signing.md](../backpatch-signing.md)                                                                        |


---

## Quick start

### H2 (Maven, single artifact)

**Local only** (no Nexus upload):

```bash
PILOT=playground/release-pilot
eval "$($PILOT/scripts/release/build-h2.sh)"
$PILOT/scripts/publish/publish-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --group-id com.h2database --artifact-id h2 \
  --staging /tmp/osera-staging-h2 \
  --module-dir "$module_dir" --jar "$jar" --pom "$pom" \
  --skip-deploy
```

Walkthrough: [h2-pilot.md](h2-pilot.md).

### Spring Framework (Gradle, all `spring-*` + BOM)

```bash
PILOT=playground/release-pilot
eval "$($PILOT/scripts/release/build-spring.sh)"
$PILOT/scripts/publish/publish-spring-staging.sh \
  --repo-dir "$repo_dir" --tag "$tag" \
  --modules-file "$modules_file" \
  --staging /tmp/osera-staging-spring \
  --skip-deploy
```

Walkthrough: [spring-pilot.md](spring-pilot.md).

**Publish to playground Nexus**: see [nexus-playground.md](nexus-playground.md).

---

## Scripts


| Script | Purpose |
| ------ | ------- |
| [`publish/publish-staging.sh`](scripts/publish/publish-staging.sh) | End-to-end orchestrator (single GAV; h2) |
| [`publish/publish-spring-staging.sh`](scripts/publish/publish-spring-staging.sh) | Multi-module orchestrator (Spring) |
| [`publish/publish-to-nexus.sh`](scripts/publish/publish-to-nexus.sh) | Upload to `…/repository/playground/` |
| [`publish/verify-publish.sh`](scripts/publish/verify-publish.sh) | SBOM, VEX, signatures, Nexus resolve |
| [`publish/stage-artifacts.sh`](scripts/publish/stage-artifacts.sh) | Copy JAR/POM/sidecars into staging |
| [`release/build-h2.sh`](scripts/release/build-h2.sh) | Clone/build h2 pilot tag (Maven) |
| [`release/build-spring.sh`](scripts/release/build-spring.sh) | Clone/build Spring pilot tag (Gradle) |
| [`release/generate-release-manifest.sh`](scripts/release/generate-release-manifest.sh) | Publish tag + git → manifest YAML |
| [`release/generate-openvex.sh`](scripts/release/generate-openvex.sh) · [`release/generate-sbom.sh`](scripts/release/generate-sbom.sh) | [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) sidecars |
| [`sign/vendor-sign.sh`](scripts/sign/vendor-sign.sh) · [`sign/finos-cosign.sh`](scripts/sign/finos-cosign.sh) | OpenPGP detached signatures |
| [`sign/generate-finos-key.sh`](scripts/sign/generate-finos-key.sh) · [`sign/generate-vendor-key.sh`](scripts/sign/generate-vendor-key.sh) | Playground key material |


Full index: run any script with `--help`. Ops for signing: [signing-setup.md](signing-setup.md).

---

## Out of scope / known gaps

- **Production FINOS keys** — playground keygen is self-signed local material only.
- **[REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) bytecode checks** — `check-bytecode.sh` only records major class-file version today; full baseline comparison is not enforced. Build JDK selection is **per pilot** (`ensure_h2_java_home` / `ensure_spring_java_home`).
- **Spring SBOM depth** — Gradle CycloneDX via init script; falls back to a coordinate-only SBOM if the plugin output is missing.

---

## More docs

- [nexus-playground.md](nexus-playground.md) — credentials, deploy URL, resolve check
- [signing-setup.md](signing-setup.md) — OpenPGP keygen, enable `--sign`
- [h2-pilot.md](h2-pilot.md) — h2 step-by-step
- [spring-pilot.md](spring-pilot.md) — Spring Framework step-by-step
- [artifact-layout.md](artifact-layout.md)

---

*2026-08-03 — Spring Gradle multi-module pilot added alongside h2.*
