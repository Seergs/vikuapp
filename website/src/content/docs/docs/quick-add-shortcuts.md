---
title: Quick-Add Shortcuts
summary: Set dates, projects, labels, and priorities as you type.
category: basics
lastUpdated: 2026-11-05
related: offline-mode
---

The quick-add sheet can read shortcuts typed straight into the title, so you can
file a task without opening the project, priority, or label pickers. The feature
is experimental and off by default. To turn it on, go to **Settings → Experimental
→ Quick-Add** and pick a dialect:

- **Vikunja** uses the same symbols as Vikunja's own add magic.
- **Todoist** uses the symbols Todoist users already know.

| Shortcut | Vikunja | Todoist | Effect |
|---|---|---|---|
| Project | `+Groceries` | `#Groceries` | Files the task in that project |
| Label | `*home` | `@home` | Adds the label. Several are allowed. A label that doesn't exist yet is created on save |
| Priority | `!1` to `!5` | `p1` to `p4` | Sets the priority |

For example, with the Vikunja dialect, `Call the plumber +"Home repairs" *urgent !4`
saves a task titled "Call the plumber" in the "Home repairs" project, with the
label "urgent" and priority 4.

How shortcuts behave:

- Quote names that contain spaces: `+"Home repairs"`.
- A shortcut counts only at the start of the title or after a space, so `a#b` stays plain text.
- Put a backslash before a symbol to keep it literal: `\#hashtag`.
- Names match regardless of case and accents, so `+groceries` finds "Groceries".
- Applied shortcuts are removed from the title. If you repeat a project or priority, only the first one applies.
- A project or label name that matches several items, or a project name that matches none, stays in the title and shows a chip so you can see what will happen on save. Pick the project or priority from the sheet's fields and the matching shortcut is written into the title for you.

While shortcuts are off, the title is saved as typed, with only the outer spaces trimmed.

## Due dates

With either dialect enabled, Quick Add also recognizes English and Spanish dates,
such as `tomorrow`, `mañana`, `next Saturday`, `en tres días`, `in two months`,
and `2027-11-15`. Add a time with `tomorrow at 6pm` or `mañana a las 18:30`.

A single valid date is highlighted. Saving `Buy milk tomorrow at 6pm` creates
"Buy milk" with that due date. Without an explicit time, the date is due at
23:59:59 in the device's time zone. Relative dates use the reference time and
device zone captured when Quick Add opens; offline synchronization keeps the
resolved instant rather than interpreting the words again. A later device-zone
change does not move the saved deadline, although its displayed local time can change.

Ambiguous, invalid, incomplete, or unsupported expressions stay in the title and
do not set a due date. For example, `today or tomorrow` does not choose either day.
If removing the date and other applied shortcuts leaves no title, Save is disabled.

Date dismissal is not available yet. To keep a recognized expression as literal
title text, turn off Quick Add Magic or edit the task after creating it. The
Developer date-preview switch only controls diagnostics; it does not control
whether dates are applied.
