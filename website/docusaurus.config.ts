import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'OSERA',
  tagline: 'A FINOS community project',
  favicon: 'img/favicon.ico',

  url: 'https://osera.finos.org',
  baseUrl: '/',

  organizationName: 'finos',
  projectName: 'backpatch-community',

  onBrokenLinks: 'throw',

  // clientModules: ['./src/clientModules/resize-observer-fix.ts'],

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: false,
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  headTags: [
    {
      tagName: 'script',
      attributes: {},
      innerHTML:
        "(function(){try{localStorage.setItem('theme','dark');}catch(e){}document.documentElement.setAttribute('data-theme','dark');})();",
    },
  ],

  themeConfig: {
    colorMode: {
      defaultMode: 'dark',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'OSERA',
      logo: {
        alt: 'OSERA Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          href: 'https://github.com/finos/backpatch-community',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Community',
          items: [
            {
              label: 'Slack',
              href: 'https://finos-lf.slack.com/',
            },
            {
              label: 'LinkedIn',
              href: 'https://www.linkedin.com/company/finosfoundation/posts/?feedView=all',
            },
          ],
        },
        {
          title: 'More',
          items: [
            {
              label: 'GitHub',
              href: 'https://github.com/finos/backpatch-community',
            },
          ],
        },
      ],
      copyright: `Copyright © ${new Date().getFullYear()} FINOS.`,
    },
    prism: {
      theme: prismThemes.nightOwlLight,
      darkTheme: prismThemes.nightOwl,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
