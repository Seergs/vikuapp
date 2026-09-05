<div align="center">

# Viku

**Native iOS client for Vikunja with beautiful design and great user experience.**

</div>

**This is not an official Vikunja Client app**

This is an opinionated mobile client for Vikunja, not a full port of the web app. 
Vikunja already has an official PWA and a [capable third-party one](https://github.com/Bassey240/vikunja-pwa), 
and both aim to mirror the web experience feature for feature. This app takes a different position.

It is built to be what you reach for when you are away from your computer: a
fast, native view of what matters today, and a frictionless way to capture a
task before you forget it. Planning, reorganizing, and deep project work stay on
the web, where they belong.

## How to Use

### Installation

You can find this app in the App Store

### Setup

Connect to your Vikunja instance using whichever method it supports:

- **API Token** — create one in Vikunja. See the [required scopes](#required-permissions).
- **Username & Password** — available when your instance has local auth enabled.
- **Single Sign-On (OIDC)** — available when your instance has an OpenID Connect
  provider configured. See [OIDC Setup](#oidc-setup) below before your first sign-in.

The app detects which of these your instance supports as you type its address,
and only shows the ones that are actually available.

## Features

### The app

- **Multiple Instances:** Connect several Vikunja accounts and switch between them.
- **Today:** An account-wide list of what is overdue, due today, and coming up across every project, behind quick filters.
- **Quick Capture:** Add a task in one tap from the tab bar, the Today home-screen widget, or the `viku://quick-add` deep link
- **Widgets:** Quickly see your daily tasks and a calendar view from your Home screen.

### Planned

- Offline Support
- Native Push Notifications


### Vikunja API Coverage

The app is a focused client, not a full port of the web UI, 
so it covers the parts of the API that matter for day-to-day mobile use

**Tasks**

- Create, update, delete
- Move a task to another project
- Account-wide search
- Duplicate (client-side copy)
- Editable fields: title, description, completion, due date, priority, labels


**Projects**

- Create, update, delete
- Nest a project under a parent

**Labels**

- Create, rename, recolor, delete
- Assign and unassign on a task

**Comments**

- Add, edit, delete

**Task relations**

- Add and remove relations between tasks

**Attachments**

- List, upload, download and preview, delete

**Not yet supported**

- Start dates, reminders, assignees, percent done, repeating tasks, task colors
- Saved filters and custom project views
- Kanban, Gantt, table views
- Team and permission management, instance settings
- Bulk editing

## OIDC Setup

If your Vikunja instance has an OpenID Connect provider configured (Authentik,
Keycloak, Authelia, Google, ...), you can sign in with it directly instead of
using an API token or a username and password.

Before your first sign-in, ask your instance admin to add this app's redirect
URI as an **additional** allowed redirect URI on the provider's client
configuration, alongside the one already used by Vikunja's own web frontend:

```
viku://oidc-callback
```

This is a one-time change on the identity provider's side, not something each
user has to do — most providers (Authentik, Keycloak, Authelia, Google, ...)
let a single client have more than one allowed redirect URI. Without it, the
provider will refuse the app's sign-in request even though the same login
works fine from a browser.

## Required Permissions

This app requires an API Token with the following permissions to work:


## Philosophy & Scope

### What it is for

- **Today at a glance.** An account-wide view of what is overdue, due today, and coming up, across every project.
- **Capturing tasks fast.** From the home-screen widget, a deep link, Siri, or a one-tap sheet, with the minimum fields needed and nothing else.
- **Checking in on projects.** A simple browsable tree with completion progress, plus enough task detail (due date, priority, labels, comments, attachments, relations) 
    to act on something without switching devices.
- **Staying out of the way.** Native, lightweight, quick to open and quick to close.

### What it is not

- Not a reimplementation of the full Vikunja web UI.
- No saved filters, no Gantt, no bulk editing.
- No team or permission administration, no instance configuration.
- Not a place for long planning sessions. It is tuned for glances and quick capture, not for restructuring your workload.
