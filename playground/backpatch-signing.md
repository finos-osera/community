# Backpatch Artifact Signing (Proposed Standard)

Provisional requirement for **vendor signing** and **FINOS co-signing** of published artifacts and sidecars.

**Status:** Proposed — not in the [OSERA catalog](https://standards.osera.finos.org/#standards) yet (future `SIGN-001`).

**Playground test:** artifact signing is **out of scope** for now. `OSERA_SKIP_SIGN=1` in [`release-pilot/config/nexus-playground.env`](release-pilot/config/nexus-playground.env). Publish to [playground Nexus](release-pilot/nexus-playground.md) without `.asc` sidecars.

**Related:** [publish.md](publish.md) · [release-pilot/nexus-playground.md](release-pilot/nexus-playground.md)

---

## Trust model

```
Vendor key  ──proves──▶  artifact built by authorized patch provider
FINOS key   ──proves──▶  FINOS vetted this vendor + release for members
```

**Both signatures are required.** Missing or invalid FINOS co-sign is a policy failure.

**Recommended v1 approach:** OpenPGP detached signatures — vendor `.asc` + FINOS `.asc.finos`. No POM or JAR format changes. Sigstore/Cosign may complement later; not a replacement for FINOS co-sign.

| Approach | Verdict |
| -------- | ------- |
| OpenPGP (GPG) FINOS root + vendor subkeys | **Primary** |
| Public-CA code-signing (OV/EV) | Optional identity enhancement |
| Self-signed X.509 (vendor only) | Do not use alone |
| Sigstore / Cosign | Future optional |

Full certificate provisioning steps: see git history / FINOS ops runbook (to be extracted to `release-pilot/signing-setup.md` when keys are provisioned).

---

## What must be signed

See [release-pilot/artifact-layout.md](release-pilot/artifact-layout.md). Every JAR, POM, CycloneDX, OpenVEX, and recipient-guidance file gets vendor `.asc` and FINOS `.asc.finos`.

---

## Scripts

Run after [`stage-artifacts.sh`](release-pilot/scripts/stage-artifacts.sh):

```bash
export VENDOR_GPG_KEY_ID=…
export FINOS_GPG_KEY_ID=…
export FINOS_GPG_PASSPHRASE=…

PILOT=playground/release-pilot
STAGING=/tmp/osera-staging-h2

$PILOT/scripts/vendor-sign.sh --staging "$STAGING" --artifact-id h2 --version 1.4.200+backpatch.001
$PILOT/scripts/finos-cosign.sh --staging "$STAGING" --artifact-id h2 --version 1.4.200+backpatch.001
```

Or use [`publish-staging.sh`](release-pilot/scripts/publish-staging.sh) with `--sign` after setting `OSERA_SKIP_SIGN=0`.

Deploy: [`publish-to-nexus.sh`](release-pilot/scripts/publish-to-nexus.sh) · Verify: [`verify-publish.sh`](release-pilot/scripts/verify-publish.sh)

Walkthrough: [release-pilot/h2-pilot.md](release-pilot/h2-pilot.md)

---

## Key material layout

```
backpatch-community/
  signing/
    finos-signing.asc
    vendors/{vendor-slug}.asc
```

Operator `~/.m2/maven.config` (optional):

```
-Daether.checksum.omitChecksumsForExtensions=.asc,.asc.finos,.openvex.json
```

---

*2026-07-23 — provisional signing standard; scripts are source of truth for commands.*
