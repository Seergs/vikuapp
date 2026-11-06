// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  integrations: [
    starlight({
      title: 'Viku',
      logo: {
        src: './src/assets/logo.png'
      },
      sidebar: [
        {
          label: 'Overview', slug: 'docs'
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
