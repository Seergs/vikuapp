---
title: Push Notifications
summary: Choose the task and project updates you want to receive.
category: setup
updated: 2026-11-06
related: server-version-support
---

# Push Notifications

Get reminders and updates from Vikunja on your iPhone. Notifications are optional, and you choose what to receive.

## Turn on notifications

1. Open **Settings → Notifications**.
2. Read and confirm the explanation, then allow notifications when iOS asks.
3. Enable your personal events. For project updates, open each project and choose the events you want.

Personal events include reminders and overdue tasks. Project events include new tasks, assignments, and comments. No project events are selected by default.

You won't receive notifications for your own actions. If you enable notifications for several accounts, you can receive updates from all of them, even when another account is open.

## Your privacy

Notifications use **Viku Relay**, a service run by the Viku developers. It receives information needed to create each notification, including the event type, task title, and project name. Viku does not share your Vikunja password or access token with Relay, and Relay does not keep a notification delivery log.

You can read the full privacy policy from the consent screen before enabling notifications. Your server needs an outgoing HTTPS connection to Relay; it does not need to be publicly accessible.

## Turn off notifications

Use the switch in **Settings → Notifications** in Viku. Deleting a webhook in Vikunja's settings does not turn this feature off: Viku may recreate it while notifications remain enabled.
