---
title: Quick Add Magic
summary: Add a task, its project, and a due date as you type.
category: basics
updated: 2026-11-12
related: offline-mode
---

# Quick Add Magic

Capture a task and organize it in one line, without opening each field separately.

## Turn on shortcuts

Open **Settings → General → Quick Add Magic** and choose **Vikunja** or **Todoist**, whichever feels familiar. Shortcuts are off by default.

## Try a task

With **Vikunja**, type:

`Buy milk tomorrow +Groceries *home`

With **Todoist**, type:

`Buy milk tomorrow #Groceries @home`

Both create “Buy milk” in your existing “Groceries” project, with the “home” label and a due date of tomorrow. A label that doesn't exist is created when you save.

| Add | Vikunja | Todoist |
|---|---|---|
| Project | `+Groceries` | `#Groceries` |
| Label | `*home` | `@home` |
| Priority | `!1` to `!5` | `p1` to `p4` |

Put names with spaces in quotes, like `+"Home repairs"`.

## Add a date

Try `tomorrow`, `next Saturday`, or `in three days`. English and Spanish dates work with either shortcut style. Include a time with `tomorrow at 6pm`; without a time, the task is due at the end of that day.

## Check before saving

Review the highlighted date and shortcut indicators. Unrecognized or ambiguous text stays in the title, so check the project and due date before saving.

To keep a recognized date as part of the title, turn off shortcuts before writing the task, or edit its title after creating it.

## Search with shortcuts

Search uses the same Quick Add Magic setting. In Vikunja mode, `*Bug login` finds tasks whose title contains “login” with the “Bug” label. In Todoist mode, use `@Bug login`. You can also filter by project and priority using the symbols above. Dates and assignees remain plain search text.

Several labels match any of them. Duplicate names include all matching labels or projects. Unknown label and project names are ignored; a query containing only unknown shortcuts shows all locally available tasks. An empty search field shows the initial screen. Escape a shortcut symbol with a backslash to search for it literally.

Search reads downloaded data and pending local changes, including offline. Results can be incomplete or outdated after a failed sync. Results are recalculated when you change the query; they do not update automatically as data syncs. With Magic off, the entire query is searched as title text.
