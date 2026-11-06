// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  integrations: [
    starlight({
      title: 'Viku',
      sidebar: [
        {
          label: 'Overview', slug: 'docs'
        },
        {
          label: 'Guides',
          items: [{ autogenerate: { "directory": "docs" } }]
        },
      ],
    }),
  ],
});
