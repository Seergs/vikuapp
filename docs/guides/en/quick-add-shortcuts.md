---
title: Quick Add Magic
summary: Set dates, projects, labels, and priorities as you type.
category: basics
updated: 2026-11-12
related: offline-mode
---

# Quick Add Magic

The quick-add sheet can read shortcuts typed straight into the title, so you can
file a task without opening the project, priority, or label pickers. Shortcuts
are off by default. To turn it on, go to **Settings → General
→ Quick Add Magic** and pick a dialect:

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
- A project or label name that matches several items, or a project name that matches none, stays in the title; only resolved shortcuts are highlighted. Pick the project or priority from the sheet's chips and the matching shortcut is written into the title for you.

While shortcuts are off, the title is saved as typed, with only the outer spaces trimmed.

## Pickers and draft selections

The project, priority, due-date, label, and reminder chips work even when Magic is off. Tap a chip to edit its selection and the up-arrow button to create the task. Existing labels can be selected together; their chip shows the first selection and a count of the rest. Creating a label from the picker is not offered yet; new labels written as shortcuts still follow the save behavior described above.

A selected chip has a × to clear its value, except for the project. The labels × clears all selected labels and applied label shortcuts. A calendar choice replaces the recognized date expression in the input; a later recognized date typed into the input takes over again. Suggestions appear only with Magic enabled and an empty title, using that dialect's symbols.

Quick Add accepts one reminder, either at a specific date/time or relative to the due date. Changing the due date recalculates the relative reminder. Removing a linked due date, through the picker or input, asks to remove both; cancelling preserves the date, reminder, and original input. Removing a reminder alone needs no confirmation and keeps the due date. Specific-date reminders are independent of the due date. These choices stay in the draft until task creation is accepted locally, including offline.

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
If removing the date and other applied shortcuts leaves no title, the create button is disabled.

To keep a recognized expression as literal title text, turn off Quick Add Magic or edit the task after creating it. The
Developer date-preview switch only controls diagnostics; it does not control
whether dates are applied.

## Search with the same syntax

Search shares the Quick Add Magic setting and token recognition. With Magic off, the query is literal title text. With it enabled, `*Bug +Work !3 login` (Vikunja) or `@Bug #Work p2 login` (Todoist) combines a title search with label, project and priority filters. Labels combine with OR; title, project and priority combine with AND. Only the first project and priority shortcut applies. Dates and assignees are not interpreted as search filters.

Names match without distinguishing case or accents, and every matching identity is included when names are duplicated. Unknown names are removed from the title query and ignored as filters, matching Vikunja web. For example, `*Bgu login` searches for “login” without a label restriction if “Bgu” does not exist locally. `*Bug *Bgu login` still restricts by “Bug” if that label exists. A query made entirely of unknown names shows every locally available task. A genuinely empty field keeps the initial search screen. Quoted names and escaped symbols follow Quick Add recognition.

Search is read-only and local: it never creates labels, sends remote search requests or triggers synchronization. It includes pending label additions/removals and local identities before server IDs are assigned. Failed uploads retain local edits. After a conflict, Search uses the cached state selected by the existing sync flow and leaves the queued edit available for resolution. It covers cached data only, so a missing or failed download can leave results incomplete or outdated. Results do not observe ongoing synchronization or edits elsewhere; changing the query recalculates them. Text matching remains a case-insensitive substring of the title, without description search or relevance ranking.
