# Signing setup (release pilot)

OpenPGP vendor + FINOS co-sign for staged artifacts. Standards proposal: [../backpatch-signing.md](../backpatch-signing.md).

Playground default remains **unsigned** (`OSERA_SKIP_SIGN=1` in `[config/nexus-playground.env](config/nexus-playground.env)`). Enable when testing signatures.

---

## Scripts


| Script                                                                       | Role                                     |
| ---------------------------------------------------------------------------- | ---------------------------------------- |
| `[scripts/sign/generate-finos-key.sh](scripts/sign/generate-finos-key.sh)`   | Self-signed FINOS playground signing key |
| `[scripts/sign/generate-vendor-key.sh](scripts/sign/generate-vendor-key.sh)` | Vendor key + FINOS uid certification     |
| `[scripts/sign/vendor-sign.sh](scripts/sign/vendor-sign.sh)`                 | Detached `.asc` on staged files          |
| `[scripts/sign/finos-cosign.sh](scripts/sign/finos-cosign.sh)`               | Detached `.asc.finos` co-signatures      |


Layout after keygen:

```
release-pilot/signing/          # gitignored private material
  gnupg/                        # GNUPGHOME
  local.env                     # key ids + passphrases (do not commit)
  finos-signing.asc             # public
  vendors/{vendor-slug}.asc     # public
```

---



## Playground keys

From repo root:

```bash
PILOT=playground/release-pilot

$PILOT/scripts/sign/generate-finos-key.sh
source $PILOT/signing/local.env

$PILOT/scripts/sign/generate-vendor-key.sh --vendor-slug acme
source $PILOT/signing/local.env   # refresh VENDOR_* exports
```

Then either:

```bash
export OSERA_SKIP_SIGN=0
# … build/stage …
$PILOT/scripts/sign/vendor-sign.sh --staging "$STAGING" --artifact-id h2 --version 1.4.200+backpatch.001
$PILOT/scripts/sign/finos-cosign.sh --staging "$STAGING" --artifact-id h2 --version 1.4.200+backpatch.001
```

Or use the orchestrator with `--sign` after `OSERA_SKIP_SIGN=0`:

```bash
$PILOT/scripts/publish/publish-staging.sh ... --sign
```

When signing is enabled, [`publish-to-nexus.sh`](scripts/publish/publish-to-nexus.sh) refuses deploy without both sidecars, uploads them as sibling files (`*.jar.asc`, `*.jar.asc.finos` — not Maven `*-vendor.asc` classifiers), and [`verify-publish.sh`](scripts/publish/verify-publish.sh) requires + verifies them for every staged target.

Optional operator Maven omit list (`~/.m2/maven.config`):

```
-Daether.checksum.omitChecksumsForExtensions=.asc,.asc.finos,.openvex.json
```

---

*Playground keys are for local tests only — not production FINOS material.*