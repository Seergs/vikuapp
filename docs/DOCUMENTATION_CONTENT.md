# In-app documentation

The app's user-facing guides live under `Viku/Documentation`. The four tracked
Markdown guides formerly in root `docs/` have moved here, with English and Spanish
versions. Root `docs/` retains repository documentation and README image assets;
untracked release notes are not part of the in-app guide catalog.

## Structure

```text
Viku/Documentation/
  Content/
    en.lproj/
      offline-mode.md
      quick-add-shortcuts.md
      push-notifications.md
      server-version-support.md
    es.lproj/
      offline-mode.md
      quick-add-shortcuts.md
      push-notifications.md
      server-version-support.md
  Models/
    DocumentationArticle.swift
  Views/
    DocumentationIndexView.swift
    BundledDocumentationArticleView.swift
    DocumentationArticleView.swift
    MarkdownContentView.swift
```

Use the same stable article ID/filename in each language. Xcode recognizes the
`.lproj` directories and copies their contents to the app's localized resources.
The language directories are preserved in the built app; duplicate resource
names are not flattened together.

`BundledMarkdownLoader` in `VikuUI` reads from a caller-supplied bundle. It chooses
the best supported language from the caller's preferences and falls back to the
English article when a translation is absent. Missing, unreadable, and empty
articles produce errors. Tests cover regional Spanish, unsupported languages,
missing translations, missing articles, empty documents, and invalid names.
The app maps errors to a localized unavailable screen.

Keep Markdown content in files rather than Swift strings or String Catalog
entries. UI labels, article titles, summaries, and category names belong in the
owning module's String Catalog, with English and Spanish translations.

`DocumentationArticle` is the ordered catalog used by the index and article
lookup. Each entry defines a stable ID/resource name, localized title and summary,
and SF Symbol. To add a guide, add an enum case and its metadata, create a Markdown
file with the same filename in both language directories, and add the title and
summary to `Viku/Localizable.xcstrings`. Keep IDs independent of translated titles.
No remote content service or synchronization is needed for bundled guides.

## Rendering and navigation

`DocumentationArticleView(title:markdown:)` accepts a resolved title and Markdown
body, owns scrolling, and uses the hosting navigation stack. The lower-level
`MarkdownContentView(markdown:)` provides Textual rendering without navigation
or scrolling. Neither view owns article lookup or language selection.

Both views remain in the app target because Textual requires iOS 18, while the
local feature packages keep an iOS 17 minimum. Settings pushes
`AppRoute.documentationArticle(id)`; only the app target's `AppDestinations`
resolves that route to the bundled article screen. All tabs, including Settings,
now have their `NavigationStack` and `AppRouter` in `MainTabView`. Settings still
resolves its local `SettingsRoute` values within the same stack.

Open **Settings → Help → Guides & Documentation** in any build. The index pushes
`AppRoute.documentationArticle(id)` for the selected catalog entry. The section
is available in release builds and has no Developer/debug gate. Returning from an
article restores the index; returning from the index restores Settings.

## Content conventions

- For new articles, use the screen title and start body sections at `##` to avoid
  duplicating it. The migrated guides retain their original `#` headings.
- Use headings, lists, links, quotes, code fences, and tables as needed.
- Reading bundled text works offline. External links and remote images require
  connectivity. Bundle essential illustrations and configure Textual's image
  resolution before relying on relative image paths.
- Internal article links need routing by stable ID when the index is implemented;
  they are not handled by the current generic renderer.
- Previews in `DocumentationArticleView.swift` cover sample content in light,
  dark, accessibility text size, and empty content. Device appearance and
  interactions still need manual validation.
