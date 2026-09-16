# OSERA

**Open Source Enterprise Resiliency Alliance** — a [FINOS](https://www.finos.org/) initiative that helps regulated institutions close open source patch-coverage gaps and operationalize remediation at scale.

This repository is the **developer landing page** for the alliance. The public site is [osera.finos.org](https://osera.finos.org).


| Audience                   | Where to go                                                    |
| -------------------------- | -------------------------------------------------------------- |
| Public / formation         | [osera.finos.org](https://osera.finos.org)                     |
| Patching standards (draft) | [standards.osera.finos.org](https://standards.osera.finos.org) |
| Risk prioritization        | [risknav.osera.finos.org](https://risknav.osera.finos.org)     |
| Source and collaboration   | [github.com/finos-osera](https://github.com/finos-osera)       |




## How OSERA is structured

Work lives in the `[finos-osera](https://github.com/finos-osera)` GitHub organization. It groups into software projects, a standards project, backpatch source lines, and task forces.

```text
OSERA (FINOS)
├── Public sites
│   ├── osera.finos.org                 this repo (website/)
│   ├── standards.osera.finos.org       remediation-standards
│   └── risknav.osera.finos.org         risk-navigator
├── Software projects
│   └── risk-navigator                  remediation prioritization tool
├── Standards
│   └── remediation-standards           open patching / attestation standards
├── Backpatch library
│   └── github.com/finos-osera-forks    public source for maintained lines
└── Task forces
    └── operations-taskforce            operational coordination
```



### Software projects


| Project            | What it is                                                                                                                          | Links                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| **Risk Navigator** | Decision-enablement tool for ranking vulnerable libraries, seeing estate exposure, and identifying upgrade or backpatch candidates. | [repo](https://github.com/finos-osera/risk-navigator) · [risknav.osera.finos.org](https://risknav.osera.finos.org) |




### Standards


| Project                              | What it is                                                                                                                                                                                                      | Links                                                                                                                             |
| ------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| **Remediation / patching standards** | Provisional evaluation draft for producing, publishing, and consuming open backpatches (fork management, provenance, release evidence, VEX/SBOM feeds, recipient test guidance). Not a ratified FINOS standard. | [repo](https://github.com/finos-osera/remediation-standards) · **[standards.osera.finos.org](https://standards.osera.finos.org)** |


### Hardened Open Source Projects library

Public repositories in `[finos-osera-forks](https://github.com/orgs/finos-osera-forks)` hold the maintained source for lines the sector still runs, often past upstream end of life. Naming, branches, release metadata and attestations follow standards defined by our Members at [standards.osera.finos.org](standards.osera.finos.org).

Source is public by default. Built, participant-ready artifacts are delivered through formation participation. Browse the org, or start from the lines already piloted on [osera.finos.org](https://osera.finos.org).

### Task forces


| Task force                | What it is                                                                                                       | Links                                                                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| **Operations Task Force** | Working repository for operational coordination of the alliance (process, intake, and cross-project operations). | [repo](https://github.com/finos-osera/operations-taskforce) · [issue tracker](https://github.com/finos-osera/operations-taskforce/issues) |


## Get involved

- Join OSERA: [osera.finos.org/#involved](https://osera.finos.org/#involved)
- Guiding principles: [osera.finos.org/guiding-principles](https://osera.finos.org/guiding-principles)
- Contribute via GitHub issues and pull requests in the relevant project (see [CONTRIBUTING.md](CONTRIBUTING.md))
- Membership: [membership@finos.org](mailto:membership@finos.org)

## How to update this website: AI-based driven developer workflow

1. Download Cursor / Claude Code / Antigravity
2. `git clone git@github.com:finos-osera/community.git`
3. Import it in Cursor / Claude Code / Antigravity
4. Switch to a feature branch: `git checkout -b mybranch`
5. Tell the agent what you want, e.g: "add this video https://www.youtube.com/watch?v=M4G2oipL4lE&list=PLXnqWU1wRiXY&index=45 to the news and media page video block"
6. `cd website; npm run start`
7. test on localhost:3000
8. if happy: `git add .; git commit -m "<describe your changes>"; git push --set-upstream origin mybranch` 
9. go in github and raise a PR
10. see the preview
11. Assign someone to review (or YOLO it if you are 100% sure)
12. merge :slightly_smiling_face:

## Governance

This project follows [FINOS open source software project governance](https://community.finos.org/docs/governance/#open-source-software-projects).

## License

Copyright 2019 Fintech Open Source Foundation

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)
