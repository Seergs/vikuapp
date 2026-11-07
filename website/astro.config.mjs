// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { satteri } from '@astrojs/markdown-satteri';
import { tableCards } from './src/plugins/table-cards.mjs';
import { site } from './src/data/site';

// https://astro.build/config
export default defineConfig({
  site: site.url,
  markdown: {
    processor: satteri({ hastPlugins: [tableCards] }),
  },
  integrations: [
    starlight({
      title: 'Viku',
      customCss: ['./src/styles/starlight.css'],
      components: {
        Sidebar: './src/components/docs/Sidebar.astro',
      },
      logo: {
        src: './src/assets/logo.png'
      },
      sidebar: [
        {
          label: 'Overview', slug: 'docs', attrs: { 'data-viku-icon': 'overview' }
        },
        {
          label: 'Guides',
          items: [{ autogenerate: { "directory": "docs" } }]
        },
      ],
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/seergs/vikuapp' }
      ],
      editLink: {
        baseUrl: 'https://github.com/Seergs/vikuapp/edit/main/website/'
      }
    }),
  ],
});
