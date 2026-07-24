# Artifact & sidecar layout

For coordinate `groupId:artifactId:version` (example: `com.h2database:h2:1.4.200+backpatch.001`):

| File | Standard | Notes |
| ---- | -------- | ----- |
| `{artifactId}-{version}.jar` | — | Primary artifact |
| `{artifactId}-{version}.pom` | — | Maven metadata |
| `{artifactId}-{version}-cyclonedx.json` | [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) | From `scripts/release/generate-sbom.sh` |
| `{artifactId}-{version}.openvex.json` | [FEED-001](https://standards.osera.finos.org/standards/feed-001-openvex-cyclonedx/) | From `scripts/release/generate-openvex.sh` |
| `{artifactId}-{version}-recipient-guidance.yaml` | [EVD-001](https://standards.osera.finos.org/standards/evd-001-change-and-test-surface/) | Generated with OpenVEX |
| `.asc` / `.asc.finos` sidecars | Proposed signing | Vendor + FINOS OpenPGP — [signing-setup.md](signing-setup.md) · [backpatch-signing.md](../backpatch-signing.md) |

**Version metadata** ([REL-003](https://standards.osera.finos.org/standards/rel-003-version-metadata/)): `<UPSTREAM>+backpatch.NNN`. Increment `NNN` to republish — never overwrite.

**Multi-module repos:** each published module gets its own coordinate row.

**Staging:** `scripts/publish/stage-artifacts.sh` copies files into an operator directory outside backpatch forks. Nothing supply-chain-related is committed into `finos-osera/backpatch-*`.

---

*Deploy classifiers: `scripts/publish/publish-to-nexus.sh`*
