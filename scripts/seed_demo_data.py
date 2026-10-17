#!/usr/bin/env python3
"""Seed a Vikunja instance with realistic demo data for App Store review / screenshots.

Meant to run once against a *fresh* Vikunja instance (e.g. a throwaway Docker
container) so App Review has something believable to click through, and so
screenshots don't look like an empty app. Uses only the Python standard
library (no `pip install` needed) and talks to the same REST endpoints the
iOS app uses (see Packages/VikunjaNetworking/.../VikunjaEndpoints.swift).

Due dates are relative to "today" at run time, so re-running the script right
before taking screenshots keeps the Overdue/Today/Upcoming buckets and the
Calendar tab looking current.

Usage:
    # Against an instance where the admin user already exists:
    python3 scripts/seed_demo_data.py --base-url https://demo.example.com \
        --username reviewer --password '...'

    # Create the user first, then seed:
    python3 scripts/seed_demo_data.py --base-url https://demo.example.com \
        --username reviewer --password '...' \
        --register --email reviewer@example.com

    # Self-signed cert on a local instance:
    python3 scripts/seed_demo_data.py --base-url https://localhost:8443 \
        --username reviewer --password '...' --insecure

Re-running against an instance that already has this data will create
duplicates (titles aren't checked for uniqueness) — point it at a fresh
instance, or wipe the Vikunja database first.

To wipe a docker-compose'd instance before re-seeding (e.g. the demo VPS,
docker-compose.yaml with bind mounts under /home/deploy/vikudemo):

    cd ~/vikudemo
    docker compose down
    sudo rm -rf /home/deploy/vikudemo/db/* /home/deploy/vikudemo/files/*
    docker compose up -d

Then re-run this script with --register (the admin user is gone too).
"""
from __future__ import annotations

import argparse
import json
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone


class VikunjaError(Exception):
    pass


class VikunjaClient:
    def __init__(self, base_url: str, insecure: bool = False):
        self.base_url = base_url.rstrip("/")
        self.token: str | None = None
        self.ssl_context: ssl.SSLContext | None = None
        if insecure:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            self.ssl_context = ctx

    def _request(self, method: str, path: str, body=None, raw_body=None, content_type=None):
        url = f"{self.base_url}{path}"
        headers = {
            "Accept": "application/json",
            # urllib's default "Python-urllib/x.y" User-Agent gets banned by
            # Cloudflare (error 1010, browser_signature_banned) on instances
            # sitting behind it, so pretend to be a regular browser.
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/128.0.0.0 Safari/537.36"
            ),
        }
        data = None
        if raw_body is not None:
            data = raw_body
            headers["Content-Type"] = content_type
        elif body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, context=self.ssl_context, timeout=30) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")
            raise VikunjaError(f"{method} {path} -> HTTP {error.code}: {detail}") from None
        except urllib.error.URLError as error:
            raise VikunjaError(f"{method} {path} -> {error.reason}") from None

        if not raw:
            return None
        return json.loads(raw)

    def probe(self):
        return self._request("GET", "/api/v1/info")

    def register(self, username: str, email: str, password: str):
        self._request(
            "POST",
            "/api/v1/register",
            body={"username": username, "email": email, "password": password},
        )

    def login(self, username: str, password: str):
        result = self._request(
            "POST", "/api/v1/login", body={"username": username, "password": password}
        )
        self.token = result["token"]

    def create_project(self, title: str, hex_color: str | None = None, parent_id: int | None = None) -> int:
        body: dict = {"title": title}
        if hex_color:
            body["hex_color"] = hex_color
        if parent_id:
            body["parent_project_id"] = parent_id
        return self._request("PUT", "/api/v1/projects", body=body)["id"]

    def create_label(self, title: str, hex_color: str) -> int:
        return self._request("PUT", "/api/v1/labels", body={"title": title, "hex_color": hex_color})["id"]

    def create_task(
        self,
        project_id: int,
        title: str,
        description: str | None = None,
        due_offset_days: int | None = None,
        priority: int = 0,
        done: bool = False,
    ) -> int:
        body: dict = {"title": title, "priority": priority, "done": done}
        if description:
            body["description"] = description
        if due_offset_days is not None:
            due = datetime.now(timezone.utc).replace(
                hour=9, minute=0, second=0, microsecond=0
            ) + timedelta(days=due_offset_days)
            body["due_date"] = due.strftime("%Y-%m-%dT%H:%M:%SZ")
        return self._request("PUT", f"/api/v1/projects/{project_id}/tasks", body=body)["id"]

    def add_label(self, task_id: int, label_id: int):
        self._request("PUT", f"/api/v1/tasks/{task_id}/labels", body={"label_id": label_id})

    def add_relation(self, task_id: int, kind: str, other_task_id: int):
        self._request(
            "PUT",
            f"/api/v1/tasks/{task_id}/relations",
            body={"relation_kind": kind, "other_task_id": other_task_id},
        )

    def add_comment(self, task_id: int, text: str):
        self._request("PUT", f"/api/v1/tasks/{task_id}/comments", body={"comment": text})

    def upload_attachment(self, task_id: int, filename: str, content: str, mime: str = "text/plain"):
        boundary = uuid.uuid4().hex
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="files"; filename="{filename}"\r\n'
            f"Content-Type: {mime}\r\n\r\n"
            f"{content}\r\n"
            f"--{boundary}--\r\n"
        ).encode("utf-8")
        self._request(
            "PUT",
            f"/api/v1/tasks/{task_id}/attachments",
            raw_body=body,
            content_type=f"multipart/form-data; boundary={boundary}",
        )


# --------------------------------------------------------------------------
# Demo data. Due dates are day offsets from "today" at run time (negative =
# overdue, 0 = today, positive = upcoming), so the Home/Calendar tabs always
# look current whenever this is run.
# --------------------------------------------------------------------------

LABELS = {
    "urgent": ("Urgent", "DF202E"),
    "bug": ("Bug", "E8590C"),
    "feature": ("Feature", "196AFF"),
    "waiting": ("Waiting", "F5A623"),
    "errand": ("Errand", "2F9E44"),
    "reading": ("Reading", "9C36B5"),
    "quick_win": ("Quick Win", "0C8599"),
    "home": ("Home", "D6336C"),
    "finance": ("Finance", "5F3DC4"),
}

PROJECTS = [
    {"key": "work", "title": "Work", "hex": "196AFF", "parent": None},
    {"key": "product_launch", "title": "Product Launch", "hex": "4DABF7", "parent": "work"},
    {"key": "team_admin", "title": "Team Admin", "hex": "74C0FC", "parent": "work"},
    {"key": "personal", "title": "Personal", "hex": "F08C00", "parent": None},
    {"key": "home_reno", "title": "Home Renovation", "hex": "2F9E44", "parent": None},
    {"key": "viku_ios", "title": "Viku iOS", "hex": "9C36B5", "parent": None},
    {"key": "japan_trip", "title": "Japan Trip 2026", "hex": "E03131", "parent": None},
    {"key": "groceries", "title": "Groceries & Errands", "hex": "37B24D", "parent": None},
]

# priority: 0 unset, 1 low, 2 medium, 3 high, 4 urgent, 5 do-now
TASKS = [
    # --- Product Launch ---
    dict(key="pl01", project="product_launch", title="Finalize Q3 roadmap deck",
         description="Sync with design and eng leads before the review.",
         due=-2, priority=4, done=False, labels=["urgent"]),
    dict(key="pl02", project="product_launch", title="Review competitor pricing analysis",
         due=-1, priority=3, done=False, labels=[]),
    dict(key="pl03", project="product_launch", title="Draft launch announcement blog post",
         description="Waiting on legal before this can go out.",
         due=0, priority=3, done=False, labels=["feature"]),
    dict(key="pl04", project="product_launch", title="Record product demo video",
         due=2, priority=2, done=False, labels=[]),
    dict(key="pl05", project="product_launch", title="Get legal sign-off on press release",
         due=3, priority=3, done=False, labels=["waiting"]),
    dict(key="pl06", project="product_launch", title="Schedule launch day social posts",
         due=5, priority=2, done=False, labels=[]),
    dict(key="pl07", project="product_launch", title="Set up analytics dashboard for launch metrics",
         due=None, priority=1, done=False, labels=["feature"]),
    dict(key="pl08", project="product_launch", title="Kickoff meeting with marketing team",
         due=-5, priority=2, done=True, labels=[]),
    dict(key="pl09", project="product_launch", title="Create landing page wireframes",
         due=-4, priority=2, done=True, labels=["feature"]),
    dict(key="pl10", project="product_launch", title="Fix broken checkout flow on staging",
         description="Repros on iOS Safari only so far.",
         due=-1, priority=4, done=False, labels=["bug", "urgent"]),
    dict(key="pl11", project="product_launch", title="Prepare launch day runbook",
         due=4, priority=3, done=False, labels=[]),
    dict(key="pl12", project="product_launch", title="Write rollback plan",
         due=6, priority=1, done=False, labels=[]),
    dict(key="pl13", project="product_launch", title="List on-call contacts",
         due=6, priority=1, done=False, labels=[]),
    dict(key="pl14", project="product_launch", title="Draft customer support FAQ",
         due=7, priority=1, done=False, labels=[]),

    # --- Team Admin ---
    dict(key="ta01", project="team_admin", title="Approve Q3 expense reports",
         due=-3, priority=2, done=False, labels=["finance", "waiting"]),
    dict(key="ta02", project="team_admin", title="Update onboarding doc for new hires",
         due=7, priority=1, done=False, labels=[]),
    dict(key="ta03", project="team_admin", title="1:1 with Sarah",
         due=1, priority=1, done=False, labels=[]),
    dict(key="ta04", project="team_admin", title="Renew team Figma license",
         due=10, priority=1, done=False, labels=["finance"]),
    dict(key="ta05", project="team_admin", title="Book conference room for offsite planning",
         due=-1, priority=1, done=True, labels=["errand"]),
    dict(key="ta06", project="team_admin", title="Submit timesheet for August",
         due=-6, priority=2, done=True, labels=["finance"]),

    # --- Personal ---
    dict(key="per01", project="personal", title="Renew passport",
         description="Needed before booking any international flights.",
         due=-7, priority=4, done=False, labels=["urgent", "waiting"]),
    dict(key="per02", project="personal", title="Book dentist appointment",
         due=2, priority=2, done=False, labels=["errand"]),
    dict(key="per03", project="personal", title="Read Atomic Habits",
         due=None, priority=1, done=False, labels=["reading"]),
    dict(key="per04", project="personal", title="Cancel unused gym membership",
         due=-2, priority=2, done=False, labels=["finance"]),
    dict(key="per05", project="personal", title="Call mom for her birthday",
         due=3, priority=3, done=False, labels=[]),
    dict(key="per06", project="personal", title="Back up phone photos",
         due=15, priority=1, done=False, labels=[]),
    dict(key="per07", project="personal", title="Finish tax documents",
         due=-10, priority=4, done=False, labels=["urgent", "finance"]),
    dict(key="per08", project="personal", title="Return library books",
         due=-1, priority=1, done=True, labels=["errand"]),
    dict(key="per09", project="personal", title="Water the plants",
         due=0, priority=1, done=True, labels=[]),
    dict(key="per10", project="personal", title="Plan weekend hike",
         due=6, priority=1, done=False, labels=[]),

    # --- Home Renovation ---
    dict(key="hr01", project="home_reno", title="Get quotes for kitchen countertop",
         description="Got 2 back, still waiting on Home Depot.",
         due=-4, priority=3, done=False, labels=["home", "waiting"]),
    dict(key="hr02", project="home_reno", title="Pick paint color for living room",
         due=1, priority=2, done=False, labels=["home"]),
    dict(key="hr03", project="home_reno", title="Schedule electrician for outlet install",
         due=5, priority=3, done=False, labels=["home", "waiting"]),
    dict(key="hr04", project="home_reno", title="Order new light fixtures",
         due=8, priority=2, done=False, labels=["home"]),
    dict(key="hr05", project="home_reno", title="Return extra tiles to hardware store",
         due=-1, priority=1, done=False, labels=["errand"]),
    dict(key="hr06", project="home_reno", title="Measure windows for new blinds",
         due=-3, priority=1, done=True, labels=["home"]),
    dict(key="hr07", project="home_reno", title="Assemble bookshelf",
         due=-8, priority=1, done=True, labels=["home"]),
    dict(key="hr08", project="home_reno", title="Research contractor reviews",
         due=None, priority=1, done=False, labels=["home"]),
    dict(key="hr09", project="home_reno", title="Renovate kitchen",
         due=30, priority=3, done=False, labels=["home"]),
    dict(key="hr10", project="home_reno", title="Choose cabinet hardware",
         due=25, priority=1, done=False, labels=["home"]),
    dict(key="hr11", project="home_reno", title="Schedule demo day",
         due=28, priority=2, done=False, labels=["home", "waiting"]),

    # --- Viku iOS (dogfooding project) ---
    dict(key="vi01", project="viku_ios", title="Fix dark mode contrast on task detail",
         due=-2, priority=3, done=False, labels=["bug"]),
    dict(key="vi02", project="viku_ios", title="Add swipe-to-complete gesture",
         due=4, priority=2, done=False, labels=["feature"]),
    dict(key="vi03", project="viku_ios", title="Investigate widget refresh delay",
         due=-1, priority=2, done=False, labels=["bug", "waiting"]),
    dict(key="vi04", project="viku_ios", title="Write unit tests for QuickAddViewModel",
         due=None, priority=1, done=False, labels=["quick_win"]),
    dict(key="vi05", project="viku_ios", title="Design empty state illustrations",
         due=12, priority=1, done=False, labels=["feature"]),
    dict(key="vi06", project="viku_ios", title="Update App Store screenshots",
         due=2, priority=3, done=False, labels=["urgent"]),
    dict(key="vi07", project="viku_ios", title="Ship TestFlight build 42",
         due=-5, priority=2, done=True, labels=[]),
    dict(key="vi08", project="viku_ios", title="Fix crash on attachment upload",
         description="Traced to a missing content-length header on large files.",
         due=-6, priority=4, done=True, labels=["bug"]),
    dict(key="vi09", project="viku_ios", title="Localize onboarding screen",
         due=20, priority=1, done=False, labels=["feature"]),
    dict(key="vi10", project="viku_ios", title="App crashes when uploading large PDF",
         description="Looks like the same root cause as the other upload crash.",
         due=-1, priority=3, done=False, labels=["bug"]),

    # --- Japan Trip 2026 ---
    dict(key="jp01", project="japan_trip", title="Book flights to Tokyo",
         description="Can't book until the passport renewal comes through.",
         due=-3, priority=3, done=False, labels=["waiting", "finance"]),
    dict(key="jp02", project="japan_trip", title="Book hotel in Kyoto",
         due=5, priority=2, done=False, labels=[]),
    dict(key="jp03", project="japan_trip", title="Create day-by-day itinerary",
         due=10, priority=2, done=False, labels=[]),
    dict(key="jp04", project="japan_trip", title="Buy JR rail pass",
         due=7, priority=2, done=False, labels=["finance"]),
    dict(key="jp05", project="japan_trip", title="Get travel insurance",
         due=2, priority=2, done=False, labels=[]),
    dict(key="jp06", project="japan_trip", title="Learn basic Japanese phrases",
         due=None, priority=1, done=False, labels=["reading"]),
    dict(key="jp07", project="japan_trip", title="Exchange currency",
         due=25, priority=1, done=False, labels=["finance"]),
    dict(key="jp08", project="japan_trip", title="Pack luggage",
         due=40, priority=1, done=False, labels=[]),
    dict(key="jp09", project="japan_trip", title="Research Tokyo neighborhoods to stay in",
         due=-5, priority=1, done=True, labels=[]),
    dict(key="jp10", project="japan_trip", title="Plan Japan trip",
         due=45, priority=3, done=False, labels=[]),

    # --- Groceries & Errands ---
    dict(key="gr01", project="groceries", title="Buy milk and eggs",
         due=0, priority=1, done=False, labels=["errand"]),
    dict(key="gr02", project="groceries", title="Pick up dry cleaning",
         due=1, priority=1, done=False, labels=["errand"]),
    dict(key="gr03", project="groceries", title="Return Amazon package",
         due=-1, priority=2, done=False, labels=["errand"]),
    dict(key="gr04", project="groceries", title="Buy birthday gift for mom",
         due=2, priority=2, done=False, labels=["errand"]),
    dict(key="gr05", project="groceries", title="Refill prescription",
         due=-2, priority=3, done=False, labels=["errand", "urgent"]),
    dict(key="gr06", project="groceries", title="Drop off recycling",
         due=0, priority=1, done=True, labels=["errand"]),
    dict(key="gr07", project="groceries", title="Buy dog food",
         due=-1, priority=1, done=True, labels=["errand"]),
]

# (task_key, relation_kind, other_task_key) — kind is the perspective of task_key.
RELATIONS = [
    ("pl11", "subtask", "pl12"),
    ("pl11", "subtask", "pl13"),
    ("pl11", "subtask", "pl14"),
    ("pl03", "blocked", "pl05"),      # blog post is blocked by legal sign-off
    ("jp01", "blocked", "per01"),     # flight booking blocked by (cross-project) passport renewal
    ("vi10", "duplicateof", "vi08"),
    ("hr08", "related", "hr01"),
    ("jp05", "precedes", "jp04"),
    ("hr09", "subtask", "hr01"),
    ("hr09", "subtask", "hr10"),
    ("hr09", "subtask", "hr11"),
    ("jp10", "subtask", "jp02"),
    ("jp10", "subtask", "jp03"),
    ("jp10", "subtask", "jp04"),
]

COMMENTS = {
    "pl01": [
        "Pushed to Monday since Sarah is OOO Friday.",
        "Deck updated with the new pricing slide.",
    ],
    "pl10": ["Reproduced on iOS Safari, filing a ticket with the payments team."],
    "jp01": ["Prices spiked, checking again next week."],
    "hr01": ["Got 2 quotes back, still waiting on a third from Home Depot."],
    "per01": ["Appointment booked for next Tuesday at 9am."],
    "vi08": [
        "Root cause was a missing content-length header on large files.",
        "Fix verified on TestFlight build 41.",
    ],
}

ATTACHMENTS = {
    "hr01": [(
        "countertop_quotes.txt",
        "Home Depot: pending\n"
        "Lowe's: $2,400 for quartz, 2-week lead time\n"
        "Local fabricator: $2,150 for quartz, 1-week lead time\n",
    )],
    "vi08": [(
        "crash_log.txt",
        "Fatal Exception: NSInvalidArgumentException\n"
        "*** -[NSURLSessionTask uploadTask:]: body exceeds content-length\n"
        "  at TaskAttachmentRepository.upload(...)\n"
        "  at TaskDetailViewModel.uploadAttachment(...)\n",
    )],
    "jp01": [(
        "flight_options.txt",
        "Option A: ANA, nonstop, $1120, Nov 3-17\n"
        "Option B: United, 1 stop, $890, Nov 3-17\n"
        "Option C: JAL, nonstop, $1265, Nov 2-16\n",
    )],
}


def seed(client: VikunjaClient):
    label_ids: dict[str, int] = {}
    for key, (title, hex_color) in LABELS.items():
        label_ids[key] = client.create_label(title, hex_color)
        print(f"  label   {title!r}")

    project_ids: dict[str, int] = {}
    for project in PROJECTS:
        parent_id = project_ids[project["parent"]] if project["parent"] else None
        project_ids[project["key"]] = client.create_project(
            project["title"], hex_color=project["hex"], parent_id=parent_id
        )
        print(f"  project {project['title']!r}")

    task_ids: dict[str, int] = {}
    for task in TASKS:
        task_ids[task["key"]] = client.create_task(
            project_ids[task["project"]],
            task["title"],
            description=task.get("description"),
            due_offset_days=task["due"],
            priority=task["priority"],
            done=task["done"],
        )
        for label_key in task["labels"]:
            client.add_label(task_ids[task["key"]], label_ids[label_key])
        print(f"  task    {task['title']!r}")

    for task_key, kind, other_key in RELATIONS:
        client.add_relation(task_ids[task_key], kind, task_ids[other_key])
    print(f"  {len(RELATIONS)} relations")

    comment_count = 0
    for task_key, comments in COMMENTS.items():
        for text in comments:
            client.add_comment(task_ids[task_key], text)
            comment_count += 1
    print(f"  {comment_count} comments")

    attachment_count = 0
    for task_key, files in ATTACHMENTS.items():
        for filename, content in files:
            client.upload_attachment(task_ids[task_key], filename, content)
            attachment_count += 1
    print(f"  {attachment_count} attachments")

    print(
        f"\nDone: {len(LABELS)} labels, {len(PROJECTS)} projects, {len(TASKS)} tasks, "
        f"{len(RELATIONS)} relations, {comment_count} comments, {attachment_count} attachments."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", required=True, help="e.g. https://demo.example.com")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--register", action="store_true", help="create the user before logging in")
    parser.add_argument("--email", help="required with --register")
    parser.add_argument("--insecure", action="store_true", help="skip TLS certificate verification")
    parser.add_argument("--yes", action="store_true", help="skip the confirmation prompt")
    args = parser.parse_args()

    if args.register and not args.email:
        parser.error("--register requires --email")

    print(f"WARNING: this will create labels, projects, tasks, comments and attachments on:")
    print(f"  {args.base_url}")
    print("Only run this against a throwaway/demo Vikunja instance.")
    if not args.yes:
        answer = input("Continue? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("Aborted.")
            sys.exit(1)

    client = VikunjaClient(args.base_url, insecure=args.insecure)

    try:
        info = client.probe()
        print(f"Connected to Vikunja {info.get('version', '?')} at {args.base_url}")

        if args.register:
            print(f"Registering user {args.username!r}...")
            client.register(args.username, args.email, args.password)

        client.login(args.username, args.password)
        print(f"Logged in as {args.username!r}. Seeding demo data...\n")
        seed(client)
    except VikunjaError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
