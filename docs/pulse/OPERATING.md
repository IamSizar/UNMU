# UNMU Pulse — operating guide

For the editors and admins who run Pulse day to day. The product spec is in
`docs/pulse/PLAN.md`; the build log is the top `HANDOFF.md` entry.

## What Pulse is
A daily briefing with four slots: **global**, **gulf**, **sharia**, **opportunity**.
Each item is either **confirmed** (a fact with a source) or **analysis** (our
reading, clearly labelled), and carries its source, evidence and verification time.
Today's Pulse requires login in the app.

## Who can do what
Staff are existing `ADMIN` accounts added in Dashboard → Pulse → Staff, each with
one or more Pulse roles. The server enforces roles on every request; the UI only hides buttons.

| Role | Can |
|---|---|
| editor | create, edit and delete own drafts; submit for review; propose a correction |
| reviewer | mark an item reviewed; reject |
| approver | approve, reject, schedule, unschedule, publish, archive; propose, apply or reject a correction |

Four-eyes rules (enforced by the server, and for the sensitive case also by a database constraint):
- Whoever wrote an item cannot review, reject or approve it.
- A **sensitive** item (every Sharia item) must be reviewed first, and its **approver must be a
  different person from its reviewer**.
- A **correction is never applied by the person who proposed it** (see below).
Approval is refused while required fields are missing. A schedule time must be in
the future and at most 30 days ahead. Rejections and corrections need a note.

## The workflow
`draft → in review → approved → scheduled → published → archived`

1. Editor fills the item (Arabic and English; a linked stock is optional) and submits.
2. Reviewer reviews (required for sensitive items); approver approves, or rejects with a note.
3. Approver schedules a time, or publishes now. The scheduler checks for due items every 60 seconds.
4. After publishing, use **Correct**, not edit. This only *proposes* the change: the live item stays
   exactly as it is. A different approver then opens the item, sees the proposed changes and the
   reason, and **applies** or **rejects** it (rejecting needs a reason). Only when it is applied does
   the item change, show the "updated/corrected" marker, keep its previous version, and notify the
   people who saved it. One proposal can be open per item at a time. A system admin holds every
   role but is still bound by these rules, so a lone admin cannot correct an item by themselves.

Every state change goes to an append-only change log (the database rejects edits to it).

## Notifications
Users choose in the app: new Pulse, updates to a previous item, corrections, changes to a saved item.
Pushes arrive in the user's app language. Tapping a push currently only opens the app.

## Deploying (manual steps)
- Migrations `0056_pulse.sql` and `0057_pulse_pending_corrections.sql` are **not** applied automatically
  in production. Apply them by hand, in order, to staging and then production, before shipping the backend.
  Down-migrations: `0057_..down.sql`, then `0056_pulse.down.sql`.
- Add the first staff in the dashboard after the migration (existing admins only).
- Tests that touch the database run only when `PULSE_TEST_DSN` is set, e.g.
  `PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" go test ./internal/repositories/...`
