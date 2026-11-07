// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { site } from './src/data/site';

// https://astro.build/config
export default defineConfig({
  site: site.url,
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
