# Server Version Support

Viku works with any Vikunja instance. It detects what your server actually
supports at runtime rather than assuming one fixed API shape, and
automatically uses Vikunja's newer v2 API when your instance offers it
(2.4.0+), falling back to v1 otherwise. This is transparent; you don't need
to do anything.

Vikunja's own plan for retiring the v1 API (per
[their docs](https://vikunja.io/docs/api-v2/), dates are their estimates
and may shift):

| | Vikunja version | Estimated date |
|---|---|---|
| v1 frozen (bugfixes only) | 2.4.0 | shipped |
| v1 deprecated | 3.0 | ~Q3/Q4 2026 |
| v1 removed | 4.0 | ~H2 2027 |

**Our plan**: Viku keeps working against v1-only instances for as long as
Vikunja's own servers do, no action needed on your end. Once Vikunja
actually removes v1 (their 4.0), we'll keep supporting instances still on
an older version for about 6 more months to give you time to upgrade, after
which running Viku against a server older than Vikunja 2.4.0 will no longer
be supported. If you can, keeping your instance on 2.4.0 or newer is the
safe long-term choice.
