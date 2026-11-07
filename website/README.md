# Viku Website

Astro hosts the product landing page at `/` and Starlight documentation at `/docs/`.
The first landing iteration is English only and links to the TestFlight beta.

## Development and validation

Use a Node version supported by the installed Astro dependencies (Node 22.23.4+
within the Node 22 line). Install with `npm ci`, then:

```sh
npm run dev -- --background
npm test
```

The dev server can be managed with `npm run astro -- dev status`,
`npm run astro -- dev logs`, and `npm run astro -- dev stop`.
`npm test` builds the static site and runs DOM integration tests against its HTML
and the actual project-demo controller. The tests cover navigation targets,
TestFlight links, no-JavaScript content, list/board switching, shared completion
state, theme initialization (including blocked storage), and docs generation.
They do not replace browser checks for responsive layout or visual quality.

## Shared design tokens

- `src/styles/tokens.css`: shared brand primitives, spacing, typography, radii,
  motion durations, and semantic color roles for light and dark themes.
- `src/styles/starlight.css`: maps those roles to Starlight's `--sl-*` properties.
  Registered through `customCss` in `astro.config.mjs`. Documentation keeps its
  existing layout and components.
- `src/styles/marketing.css`: marketing layout styles and resets, imported only
  by `MarketingLayout.astro`, so they do not affect the docs.

Use `--viku-color-*` semantic roles in components. Reserve primitive palette
values for defining roles, and keep component-specific dimensions local. The
Starlight adapter should reference tokens rather than duplicate their values.
Motion should use the duration tokens, which become zero with Reduce Motion.
Labels, task priorities, and Quick Add date/priority/project chips have semantic
color roles here too. Links use the primary brand blue in light mode and a
brighter brand blue for dark backgrounds.

The landing and docs share Starlight's `starlight-theme` storage preference and
`data-theme` attribute. The landing reads the preference before first paint;
System mode follows CSS media queries, including live OS theme changes. If
storage is unavailable, the landing still lets visitors change the current theme.
The system preference also works without JavaScript.

## Content and components

- `src/data/site.ts`: domain, contact email, and TestFlight destination.
- `src/layouts/MarketingLayout.astro`: metadata, header, footer, and theme picker.
- `src/components/ui/`: app icon, server SVG, and beta link shared by marketing
  sections. App icons use quality-100 WebP variants up to the source's native
  dimensions for Retina displays; generated files stay in ignored build output.
- `src/components/landing/ProjectDemo.astro`: illustrative, locally interactive
  list and board. Uses no backend or persistence. Both views share task completion
  state; completion does not move cards between the example workflow columns.
- `src/pages/index.astro`: landing sections, adapted from the product mockup.

Quick Add copy reflects the documented experimental opt-in and uses Vikunja
shortcuts. Notification copy identifies the optional relay; offline copy links
to documented limitations. The website currently states the app's iOS 26.2 floor.

## Pending for later iterations

- A higher-resolution app icon can replace the current 256px source. Keep the
  full-resolution master outside Git and export an optimized 512px web asset,
  rather than adding the master to this repository. The hero's 104px icon needs
  312 source pixels for a full 3× render; current variants stop at 256px.
- Replace the reserved phone frame in `index.astro` with a real app screenshot.
  The mockup's external runtime and `todo-app-scene.jsx` are not required.
- Replace `/privacy/`'s explicitly provisional content with the final policy.
- Complete browser review on mobile and desktop, in both themes and with Reduce
  Motion, before treating the landing as final.
- Apply any further docs-specific visual refinements using the shared tokens.
- Add languages and App Store availability when ready.

The original `.dc.html` mockup is a design reference, not a runtime dependency.
