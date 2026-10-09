# Push Notifications

Vikunja doesn't send push notifications to iOS on its own, Apple only hands out those
credentials to the app's own developers. So when you turn on notifications in Viku, there's a
small relay involved: Viku Relay, a service we (the Viku developers) run, that sits between
your Vikunja instance and your iPhone.

Here's how the pieces fit together, and the handful of things worth knowing about how it
behaves.

## How it works

Vikunja already has a feature called webhooks: tell it "when X happens, send a message to this
URL", and it does. When you enable notifications in Viku, the app points some of these
webhooks at Viku Relay. When Vikunja fires one, the relay turns it into an actual push
notification and sends it to your phone through Apple's push service.

Nothing is set up on your instance until you turn notifications on. Viku Relay doesn't know
you exist before that.

## Turning it on

**Settings → Notifications**. You'll see a short explanation of what's about to happen, and
need to confirm it before anything is created. iOS will then ask for notification permission,
same as any other app would.

There are two independent things you can enable:

- **Your events.** Things that happen to you personally, regardless of which project they're
  in, things like a task reminder firing, or a task becoming overdue. This mirrors what
  Vikunja's own web notification bell would tell you.
- **Project events, per project.** Open a project, pick what you want to hear about there: new
  tasks, tasks assigned to you, comments, and so on. Nothing is selected by default, you choose
  project by project.

Whatever you enable, you won't get notified for your own actions. Commenting on a task doesn't
get you a notification telling you that you commented on a task.

If you use more than one Vikunja account in Viku, notifications work for all of the accounts
you've enabled them on, not just whichever one happens to be open at the time. That's the
point of a notification, really, telling you about something while you're not looking at it.

## Turning it off

The toggle in Viku's **Settings → Notifications** screen is what actually matters. Switching it
off deletes the webhooks Viku created on your Vikunja instance and unregisters your device from
Viku Relay. Nothing is left behind on either side.

### "I deleted the webhook from Vikunja's own settings instead, why am I still getting notified?"

These webhooks are just regular webhooks, so you can see them sitting in Vikunja's own settings
pages like any other. Deleting one from there doesn't tell Viku anything, though. As far as the
app is concerned, the toggle is still on.

So the next time Viku checks in, which happens when you open the Notifications screen, and
also every time you open the app, it notices the webhook it expects isn't there anymore and
quietly recreates it. From where you're sitting, nothing seems to have happened, notifications
just keep arriving.

If your goal is to actually stop them, use the toggle in Viku. Deleting the webhook on
Vikunja's side by itself won't do it, Viku will just put it back.

## Two rough edges worth knowing about

**A leftover, dead webhook can stick around on your Vikunja instance if your login had already
expired when you turned notifications off (or deleted that connection).**

Cleanly turning things off is two separate steps: unregistering from the relay, which Viku can
always do, and deleting the webhook entry itself from your Vikunja server, which needs a valid,
logged-in session with that server. If that session had already expired, Viku can still stop
pushes from reaching your phone, but it has no way to log back in on your behalf just to remove
one webhook entry. It stays configured on your instance, quietly pointed at a relay that will
now reject anything it sends. It's inert, not a privacy issue, but if the clutter bothers you,
you can delete it by hand from Vikunja's own webhook settings.

**With more than one Vikunja account on the same phone, notifications for each one can recover
at different times after something like a reinstall.**

Reinstalling the app, or restoring your phone from a backup, changes the token Apple uses to
reach your device. The relay only learns this the next time it actually tries to push something
to an affected account, at which point it cleans up that one account's registration. Your other
accounts on the same device aren't touched until they each have their own event to try and
deliver. In practice: an account you use daily recovers almost immediately, a quieter one might
not catch up until something actually happens in it.

## What the relay actually sees

Enough to build the notification: the event type, the task title, and the project name. Your
Vikunja password or access token never leaves your device, and the relay doesn't keep a log of
what it delivers. The consent screen links to the relay's own privacy page if you want the full
detail on what's stored and for how long.

## Good to know

- Your Vikunja instance doesn't need to be reachable from the internet, it can sit on a home
  server or a private network with no inbound access at all. What it does need is outbound
  access, a way to reach Viku Relay over HTTPS, since it's the one sending the webhook request.
- This whole feature is optional. If you never turn it on, nothing else about how you use Viku
  changes.
