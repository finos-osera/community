# Backpatch Artifact Signing (Proposed Standard)

Provisional requirement for **vendor signing** and **FINOS co-signing** of published artifacts and sidecars.

**Status:** Proposed — not in the [OSERA catalog](https://standards.osera.finos.org/#standards) yet (future `SIGN-001`).

**Related:** [publish.md](publish.md) · [release-pilot/signing-setup.md](release-pilot/signing-setup.md)

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
| OpenPGP (GPG) FINOS root + vendor keys certified by FINOS | **Primary** |
| Public-CA code-signing (OV/EV) | Optional identity enhancement for the FINOS org key |
| Self-signed X.509 (vendor only) | Do not use alone |
| Sigstore / Cosign | Future optional dual-sign |

---

## What must be signed

See [release-pilot/artifact-layout.md](release-pilot/artifact-layout.md). Every published JAR, POM, CycloneDX, OpenVEX, and recipient-guidance file gets vendor `.asc` and FINOS `.asc.finos`.

---

## Implementation

Runnable OpenPGP tooling, Maven deploy/verify wiring, and playground key generation live in the release pilot:

- Ops guide: [release-pilot/signing-setup.md](release-pilot/signing-setup.md)
- Scripts: `release-pilot/scripts/sign/`
- Deploy + verify: `release-pilot/scripts/publish/`

---

*2026-07-24 — standards proposal; implementation in release-pilot.*
