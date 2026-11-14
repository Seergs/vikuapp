---
title: Quick Add Magic
summary: Add a task, its project, and a due date as you type.
category: basics
updated: 2026-11-13
related: offline-mode
---

# Quick Add Magic

Capture a task and organize it in one line, without opening each field separately.

## Turn on shortcuts

Open **Settings → This connection → Quick Add Magic** and choose **Off**, **Vikunja**, or **Todoist**. The app uses the setting saved on your Vikunja server: changing it also changes the mode used on the web. Without a saved preference, Vikunja uses its own syntax.

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

Search uses the same shortcuts for labels, projects and priority. Try `*Bug login` (Vikunja) or `@Bug login` (Todoist) to find titles containing “login” with the “Bug” label. With Magic off, search matches title text only.
