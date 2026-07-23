# Release pilot

Runnable operator toolkit for the `backpatch-h2` pilot and fleet rollout. Scripts live under `scripts/`; release manifests are generated from git tags (not checked in).

**Standards:** [REL-001](https://standards.osera.finos.org/standards/rel-001-build-process/) · [REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) · [REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/) · [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/)

**Related:** [nexus-playground.md](nexus-playground.md) · [../release-process.md](../release-process.md) · [../publish.md](../publish.md)

---

## Status


| Item               | Status                                                                                                                 |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Pilot scripts      | **Ready**                                                                                                              |
| Nexus test target  | `playground` repo — [nexus-playground.md](nexus-playground.md)                                                         |
| Pilot manifest     | Generated from git by `publish-staging.sh` (or `[generate-release-manifest.sh](scripts/generate-release-manifest.sh)`) |
| Artifact signing   | **Skipped** — `OSERA_SKIP_SIGN=1` in `[config/nexus-playground.env](config/nexus-playground.env)`                      |
| Production signing | Later — [../backpatch-signing.md](../backpatch-signing.md)                                                             |


---

## Quick start

**Local only** (no Nexus upload):

```bash
PILOT=playground/release-pilot
eval "$($PILOT/scripts/build-h2.sh)"
$PILOT/scripts/publish-staging.sh \
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
3. **Deploy** — upload the staged artifacts to the `playground` Nexus repo via `mvn deploy:deploy-file` (`publish-to-nexus.sh`).
4. **Validate** — check staged SBOM/OpenVEX (bom-ref, CVE statements), then confirm the coordinate resolves from Nexus with `mvn dependency:get` (`verify-publish.sh`).

---

## Scripts


| Script                                                                                                | Purpose                                                                                      |
| ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `[publish-staging.sh](scripts/publish-staging.sh)`                                                    | End-to-end orchestrator (sign skipped by default)                                            |
| `[publish-to-nexus.sh](scripts/publish-to-nexus.sh)`                                                  | Upload to `…/repository/playground/`                                                         |
| `[verify-publish.sh](scripts/verify-publish.sh)`                                                      | SBOM, VEX, Nexus resolve                                                                     |
| `[build-h2.sh](scripts/build-h2.sh)`                                                                  | Clone/build pilot tag                                                                        |
| `[generate-release-manifest.sh](scripts/generate-release-manifest.sh)`                                | Publish tag + git → manifest YAML (+ optional sidecars)                                      |
| `[generate-openvex.sh](scripts/generate-openvex.sh)` · `[generate-sbom.sh](scripts/generate-sbom.sh)` | [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) sidecars |
| `[vendor-sign.sh](scripts/vendor-sign.sh)` · `[finos-cosign.sh](scripts/finos-cosign.sh)`             | Deferred — use `--sign` when keys exist                                                      |


Full index: run any script with `--help`.

---

## Out of scope (playground phase)

- **Artifact signing** — vendor GPG + FINOS co-sign are deferred (`OSERA_SKIP_SIGN=1`). Planned model: [../backpatch-signing.md](../backpatch-signing.md); scripts exist (`vendor-sign.sh`, `finos-cosign.sh`) for a later `--sign` run.
- **[REL-002](https://standards.osera.finos.org/standards/rel-002-bytecode-compatibility/) bytecode checks** — `check-bytecode.sh` only records major class-file version today; full baseline comparison is not enforced. Build JDK selection is **h2-specific** (hardcoded JDK 17 in `ensure_h2_java_home`); a generic path should read toolchain requirements from each backpatch repo (POM, `build.sh`, or OSERA metadata) instead of pilot special cases.

---

## More docs

- [nexus-playground.md](nexus-playground.md) — credentials, deploy URL, resolve check
- [h2-pilot.md](h2-pilot.md) — step-by-step walkthrough
- [artifact-layout.md](artifact-layout.md)

---

*2026-07-23 — playground Nexus test; signing out of scope for now.*