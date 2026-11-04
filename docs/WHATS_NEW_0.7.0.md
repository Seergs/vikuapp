# What's New: offline release draft

The app now bundles `Viku/Resources/whats-new_en.json` and
`Viku/Resources/whats-new_es.json`. The existing provider loads these directly;
Xcode's synchronized app group includes them as resources.

`0.7.0` and `2026-11-04` are draft release metadata, not a published release.
Confirm the version and publication date before shipping. The minimum app version
is `0.7.0`; Debug bypasses that floor, so returning users can preview the content
on the next launch after onboarding. A release already marked as seen will not
appear again. Fresh onboarding intentionally skips the announcement.

## Draft checklist

- [x] English and Spanish release copy.
- [x] Designed offline hero artwork.
- [x] Reset confirmation toast and simplified version header.
- [ ] Supply the three guide images and replace their `null` fields.
- [ ] Review the guide on device with the final images.
- [ ] Confirm release version and publication date before marking ready.

## Artwork to supply

The hero uses the supplied Cloudflare image URL in both languages:

`https://static.viku.dev/cdn-cgi/image/width=1200,quality=80,format=auto/img/whats-new/offline-support/viku-portada-offline.png`

The three guide image fields are still `null`, so those views reserve blank image
areas. Replace them with public HTTPS URLs after artwork is available.
Do not use private server attachments or URLs requiring authentication.

| Image | JSON location | Suggested composition |
| --- | --- | --- |
| Offline hero (configured) | `hero.image` | Designed illustration: simplified task cards, completion and pending sync cues, with a soft blue background. |
| Prepare offline data | `guides.offline-mode.steps[0].image` | A loaded project with its tasks, while connected. |
| Work offline | `guides.offline-mode.steps[1].image` | A downloaded project board with a locally created task or a pending column move, while offline. |
| Review synchronization | `guides.offline-mode.steps[2].image` | Settings → Pending Sync showing pending operations and a readable failure reason. |

Use normal portrait simulator screenshots as source material, at native
resolution. For the three guide images, prepare focused detail crops rather than shrinking a full
phone screen into each image. Do not stretch screenshots or add device frames.

- Hero: crop the offline status and two or three task rows, including one pending
  change. This should communicate the feature at a glance.
- Preparation: crop the project heading and a few loaded task rows.
- Offline work: crop the relevant board columns and the locally created or moved
  task. Hide unrelated columns rather than fitting the entire board.
- Synchronization: crop the Pending Sync heading and one or two operations,
  including a readable failure reason.

Export PNG panels around 1200 × 600 pixels. Keep the key UI within the central
80% and leave modest breathing room around it. At the rendered size, labels must
still be readable. If a crop needs context, compose it on a plain background
matching the screenshot, without adding explanatory text. Use the same theme and
demo account across all images. Capture localized UI for each language if needed.

The current hero fills a 180-point-high frame and guide images fill
150-point-high frames; edges may crop according to device width. This format
works with those frames without changing the UI. Full portrait screenshots would
need a separate presentation treatment to stay legible and avoid cropping.

Use public HTTPS image URLs. Publish a new URL when replacing an image, because
artwork is cached by URL. Feature rows use SF Symbols and need no images.

## Copy style

Keep the subtitle to one short line of thought and each feature description to
one sentence. The main screen presents benefits; the guide retains preparation,
sync instructions, and essential offline limitations. Full operational details
remain in `docs/offline-mode.md`.

## Content evidence

Scope: `git log v0.6.0-build.1..HEAD`, through `971d75b`.
The previous tag is dated 2026-10-29. No earlier features are presented as new.

- Offline projects, tasks, labels, relations, comments, reminders, and saved-filter
  caching/mutations: repository cutovers and sync changes after the tag;
  user-facing behavior also documented in `docs/offline-mode.md`.
- Offline project Kanban: #326–#330; column limits/recovery: #337.
  Saved-filter boards remain online-only (#331 and `ARCHITECTURE.md`).
- Pending operations, conflict recovery, and failure reasons: #304, #339–#340,
  #343, #355. Reload discards all unsynced account changes, with replacement
  committed only after a successful download.
- Description checkboxes: #345. Calendar interaction/offline improvements:
  #347, #350–#354. Quick-add matching: #344.
- Widget cache fallback: #302. Deleted subprojects: #348.
  Rapid completions: #342. Kanban pagination: #321.
- Previous-version history comes from `docs/TESTFLIGHT_0.6.0.md` and the tag date.

No unsupported performance figures, compatibility claims, external documentation
URLs, or unimplemented deep links are included.
