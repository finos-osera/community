# Release pilot

Runnable operator toolkit for the `backpatch-h2` pilot and fleet rollout. Scripts live under `scripts/{release,publish,sign}/`; release manifests are generated from git tags (not checked in).

**Standards:** [REL-001](https://standards.osera.finos.org/standards/rel-001-build-process/) · [REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) · [REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) · [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/)

**Related:** [nexus-playground.md](nexus-playground.md) · [signing-setup.md](signing-setup.md) · [../release-process.md](../release-process.md) · [../publish.md](../publish.md) · [../backpatch-signing.md](../backpatch-signing.md)

---

## Status


| Item               | Status                                                                                                                               |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Pilot scripts      | **Ready**                                                                                                                            |
| Nexus test target  | `playground` repo — [nexus-playground.md](nexus-playground.md)                                                                       |
| Pilot manifest     | Generated from git by `publish/publish-staging.sh` (or [`release/generate-release-manifest.sh`](scripts/release/generate-release-manifest.sh)) |
| Artifact signing   | **Skipped by default** — `OSERA_SKIP_SIGN=1`; enable via [signing-setup.md](signing-setup.md)                                        |
| Production signing | Proposed — [../backpatch-signing.md](../backpatch-signing.md)                                                                        |


---

## Quick start

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

**Publish to playground Nexus**: see [nexus-playground.md](nexus-playground.md).

End-to-end, `build-h2.sh` + `publish-staging.sh` do the following:

1. **Build** — clone `backpatch-h2` at the publish tag and run `mvn package`.
2. **Sidecars** — derive release manifest from git (`baseline..tag` commits), then generate OpenVEX, CycloneDX SBOM, and recipient guidance; copy JAR, POM, and sidecars into the staging dir.
3. **Sign** (optional) — vendor `.asc` + FINOS `.asc.finos` when `OSERA_SKIP_SIGN=0` or `--sign`.
4. **Deploy** — upload staged artifacts to the `playground` Nexus repo via `mvn deploy:deploy-file`.
5. **Validate** — check SBOM/OpenVEX (and signatures when enabled), then confirm the coordinate resolves from Nexus.

---

## Scripts


| Script | Purpose |
| ------ | ------- |
| [`publish/publish-staging.sh`](scripts/publish/publish-staging.sh) | End-to-end orchestrator |
| [`publish/publish-to-nexus.sh`](scripts/publish/publish-to-nexus.sh) | Upload to `…/repository/playground/` |
| [`publish/verify-publish.sh`](scripts/publish/verify-publish.sh) | SBOM, VEX, signatures, Nexus resolve |
| [`publish/stage-artifacts.sh`](scripts/publish/stage-artifacts.sh) | Copy JAR/POM/sidecars into staging |
| [`release/build-h2.sh`](scripts/release/build-h2.sh) | Clone/build pilot tag |
| [`release/generate-release-manifest.sh`](scripts/release/generate-release-manifest.sh) | Publish tag + git → manifest YAML |
| [`release/generate-openvex.sh`](scripts/release/generate-openvex.sh) · [`release/generate-sbom.sh`](scripts/release/generate-sbom.sh) | [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) sidecars |
| [`sign/vendor-sign.sh`](scripts/sign/vendor-sign.sh) · [`sign/finos-cosign.sh`](scripts/sign/finos-cosign.sh) | OpenPGP detached signatures |
| [`sign/generate-finos-key.sh`](scripts/sign/generate-finos-key.sh) · [`sign/generate-vendor-key.sh`](scripts/sign/generate-vendor-key.sh) | Playground key material |


Full index: run any script with `--help`. Ops for signing: [signing-setup.md](signing-setup.md).

---

## Out of scope / known gaps

- **Production FINOS keys** — playground keygen is self-signed local material only.
- **[REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) bytecode checks** — `check-bytecode.sh` only records major class-file version today; full baseline comparison is not enforced. Build JDK selection is **h2-specific** (hardcoded JDK 17 in `ensure_h2_java_home`).

---

## More docs

- [nexus-playground.md](nexus-playground.md) — credentials, deploy URL, resolve check
- [signing-setup.md](signing-setup.md) — OpenPGP keygen, enable `--sign`
- [h2-pilot.md](h2-pilot.md) — step-by-step walkthrough
- [artifact-layout.md](artifact-layout.md)

---

*2026-07-24 — scripts under release/publish/sign; signing wired into deploy + verify.*
