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
| editor | create, edit and delete own drafts; submit for review |
| reviewer | mark an item reviewed; reject |
| approver | approve, reject, schedule, unschedule, publish, archive, correct a published item |

Four-eyes rule: whoever wrote an item cannot review, reject or approve it.
A **sensitive** item must be reviewed by a reviewer before it can be approved.
Approval is refused while required fields are missing. A schedule time must be in
the future and at most 30 days ahead. Rejections and corrections need a note.

## The workflow
`draft → in review → approved → scheduled → published → archived`

1. Editor fills the item (Arabic and English; a linked stock is optional) and submits.
2. Reviewer reviews (required for sensitive items); approver approves, or rejects with a note.
3. Approver schedules a time, or publishes now. The scheduler checks for due items every 60 seconds.
4. After publishing, use **Correct**, not edit. Each correction is versioned, shown in the item's
   history, and readers who saved the item are notified.

Every state change goes to an append-only change log (the database rejects edits to it).

## Notifications
Users choose in the app: new Pulse, updates to a previous item, corrections, changes to a saved item.
Pushes arrive in the user's app language. Tapping a push currently only opens the app.

## Deploying (manual steps)
- Migration `backend/migrations/0056_pulse.sql` is **not** applied automatically in production.
  Apply it by hand to staging, then production, before shipping the backend. Down-migration: `0056_pulse.down.sql`.
- Add the first staff in the dashboard after the migration (existing admins only).
- Tests that touch the database run only when `PULSE_TEST_DSN` is set, e.g.
  `PULSE_TEST_DSN="host=/tmp dbname=unmu_pulse_dev sslmode=disable" go test ./internal/repositories/...`
