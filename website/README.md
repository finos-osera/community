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

## Deployment

Netlify is the default hosting platform for FINOS websites. Use:

- Working directory: `website`
- Build command: `npm run build`
- Publish directory: `website/build`

To request a `*.finos.org` domain, email [help@finos.org](mailto:help@finos.org).
