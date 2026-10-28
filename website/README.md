# OSERA Website

The homepage is a plain HTML file at [`index.html`](./index.html). Edit that file directly and paste in your page content.

Static assets live in [`img/`](./img/). Reference them from HTML with paths like `/img/favicon.ico`.

Deployed at [osera.finos.org](https://osera.finos.org).

## Local development

- Node.js 20 or higher
- From the `website` directory:

```sh
npm install
npm run start
```

The site runs at [http://localhost:3000](http://localhost:3000).

## Build

```sh
npm run build
```

Output is written to `build/` (`index.html` plus `img/`).

### Google Analytics configuration

Set a Google Analytics Measurement ID at build time to enable tracking:

macOS/Linux:

```sh
GA_MEASUREMENT_ID=G-XXXXXXXXXX npm run build
```

PowerShell:

```powershell
$env:GA_MEASUREMENT_ID="G-XXXXXXXXXX"
npm run build
```

Command Prompt:

```bat
set GA_MEASUREMENT_ID=G-XXXXXXXXXX && npm run build
```

If `GA_MEASUREMENT_ID` is not set, the build still succeeds and analytics blocks are stripped from output HTML.

## Deployment

Netlify is the default hosting platform for FINOS websites. Use:

- Working directory: `website`
- Build command: `npm run build`
- Publish directory: `website/build`

To request a `*.finos.org` domain, email [help@finos.org](mailto:help@finos.org).

## Published feed and VEX navigator

The homepage loads `https://feed.finos.org/stats/metrics.json`. `vex.html` loads
`https://feed.finos.org/openvex.json` once per visit and searches in the browser.
No backend, credentials, bundled feed snapshot or extra runtime dependencies are needed.
The feed must permit cross-origin requests from the site. Both views show their own
publication timestamp; totals are never combined across the two snapshots.

The navigator supports library/CVE/alias/version/PURL search, status and supplier
filters, library drill-down, 25 results per page and shareable query parameters.
An ecosystem filter appears when the feed contains more than one ecosystem.
Original statements are rendered as text, including additional evidence fields.
A fixed entry is a unique vulnerability and product identifier pair with `fixed`
status; different statements remain inspectable. Non-CVE identifiers do not inflate
the distinct-CVE total. This is a VEX explorer, not the complete library catalog.

A validated last successful feed is saved in browser local storage when available.
Network failures (including a 15-second timeout) may fall back to that snapshot,
clearly marked as unavailable for refresh with its source date and age. With no
valid cache, the page shows an error and Retry, never fabricated zero counters.
The feed's existing HTTP cache headers are respected. Clear site data to remove
saved snapshots. Blocked/full local storage does not prevent a fresh load.

Run `npm test` for parsing, counting, filtering, malformed data and fallback tests.
Run `npm run build`; serve `build/` to preview both `/` and `/vex.html`.

The default release scope selects the highest numeric `-osera-N` tag separately
for each version prefix, library, ecosystem and supplier in VEX. It does not
collapse separate maintained version lines or infer a release date from a VEX
statement timestamp. Version schemes without an OSERA sequence remain visible.
Selection happens before search so a historical search hit cannot become “latest”.
Users can switch to all releases or inspect other releases from a library row.
Visible, individually removable chips expose every active query/filter, including
the selected library. Clearing filters preserves the separately visible release
scope and view controls. The scope is included in shared URLs when non-default.

Library and release rows show fixes declared for that exact version, including
carried-forward fixes when the publisher includes them. They are not incremental
patch counts, and no union of earlier-version statements is inferred. “New in this
release” needs producer evidence identifying that distinction and is not currently
shown. CVE and GHSA links use allowlisted NVD/GitHub URL patterns and open a new tab.
