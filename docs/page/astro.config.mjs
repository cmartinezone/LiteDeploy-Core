// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://litedeploy.example',
  integrations: [
    starlight({
      title: 'LiteDeploy',
      description:
        'Bare-metal Windows deployment — BootInitializer, engine, PreCheck, SelectWorkflow, and OEM catalogs.',
      logo: {
        src: './src/assets/logo.svg',
      },
      favicon: '/favicon.svg',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/cmartinezone/LiteDeploy-Core' },
      ],
      customCss: ['./src/styles/theme.css'],
      editLink: {
        baseUrl: 'https://github.com/cmartinezone/LiteDeploy-Core/edit/dev/docs/page/',
      },
      sidebar: [
        {
          label: 'User Guide',
          items: [
            { label: 'Overview', slug: 'guides/overview' },
            { label: 'Getting Started', slug: 'guides/getting-started' },
            { label: 'Deployment Modes', slug: 'guides/deployment-modes' },
          ],
        },
        {
          label: 'Code Reference',
          items: [
            { label: 'Architecture', slug: 'code-reference/architecture' },
            { label: 'BootInitializer', slug: 'code-reference/bootinitializer' },
            { label: 'Deployment Engine', slug: 'code-reference/deployment-engine' },
            { label: 'PreCheck', slug: 'code-reference/precheck' },
            { label: 'SelectWorkflow', slug: 'code-reference/select-workflow' },
            { label: 'Progress', slug: 'code-reference/progress' },
            { label: 'UiHost', slug: 'code-reference/uihost' },
            { label: 'LogWriter', slug: 'code-reference/logwriter' },
            { label: 'HostShell', slug: 'code-reference/hostshell' },
            { label: 'BootConfig', slug: 'code-reference/bootconfig' },
          ],
        },
        {
          label: 'Manager',
          items: [
            { label: 'Manager Overview', slug: 'manager/overview' },
          ],
        },
        {
          label: 'Help',
          items: [
            { label: 'Dev Branch', slug: 'help/dev-branch' },
          ],
        },
      ],
    }),
  ],
});
