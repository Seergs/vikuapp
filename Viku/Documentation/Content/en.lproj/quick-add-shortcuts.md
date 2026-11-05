# Quick-Add Shortcuts

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
