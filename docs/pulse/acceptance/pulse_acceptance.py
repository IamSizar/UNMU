#!/usr/bin/env python3
"""
pulse_acceptance.py — API-level acceptance run for UNMU Pulse (spec section 22).

Runs against a STAGING backend only. It creates throw-away users and items
(dated in 1992 so nothing collides with a real day), exercises the whole
editorial cycle and the public reads, prints PASS/FAIL per criterion, and
exits non-zero if any fails.

  STAGING_API=https://backend-staging-xxxx.up.railway.app/api \
  STAGING_DB_URL=postgresql://...  PSQL=/path/to/psql  python3 pulse_acceptance.py

The DB URL is used only to mark the throw-away users' e-mail verified and to
give them the ADMIN role (staging has no mail server; Pulse staff must be ADMIN
accounts). It refuses to run against a production-looking URL.
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = os.environ["STAGING_API"].rstrip("/")
DB = os.environ["STAGING_DB_URL"]
PSQL = os.environ.get("PSQL", "psql")
if "production" in API:
    sys.exit("refusing to run against a production-looking URL")

RESULTS = []


def check(name, ok, detail=""):
    """Record and print one criterion."""
    RESULTS.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail and not ok else ""))


def call(method, path, token=None, body=None):
    """One JSON HTTP call; returns (status, parsed body)."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode(errors="replace")[:200]}


def sql(q):
    out = subprocess.run([PSQL, DB, "-Atc", q], capture_output=True, text=True)
    if out.returncode:
        sys.exit("psql failed: " + out.stderr)
    return out.stdout.strip()


# ─── Users ────────────────────────────────────────────────────────────────
stamp = str(int(time.time()))
PASSWORD = "Accept-" + stamp + "-Pw!"


def make_user(label, admin=False):
    email = f"pulse-{label}-{stamp}@example.test"
    status, _ = call("POST", "/auth/register", body={"email": email, "password": PASSWORD, "name": label})
    if status not in (200, 201):
        sys.exit(f"register {label} failed: {status}")
    role = ", role = 'ADMIN'" if admin else ""
    sql(f"UPDATE users SET email_verified_at = NOW(){role} WHERE email = '{email}'")
    status, body = call("POST", "/auth/login", body={"email": email, "password": PASSWORD})
    if status != 200:
        sys.exit(f"login {label} failed: {status} {body}")
    return {"email": email, "token": body.get("token"), "id": int(sql(f"SELECT id FROM users WHERE email = '{email}'"))}


admin = make_user("admin", admin=True)
editor = make_user("editor", admin=True)
reviewer = make_user("reviewer", admin=True)
approver = make_user("approver", admin=True)
reader = make_user("reader")
reader2 = make_user("reader2")

staff_status = [
    call("POST", "/pulse-admin/staff", admin["token"], {"email": u["email"], "role": r})[0]
    for u, r in [(editor, "editor"), (reviewer, "reviewer"), (approver, "approver")]
]
check("9 staff roles can be assigned by an admin", all(s in (200, 201) for s in staff_status), str(staff_status))

# ─── Items ────────────────────────────────────────────────────────────────
DAY = "1992-03-"
verified = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 3600))


def item_body(slot, day, analysis=False, sensitive=False, stock=None):
    return {
        "pulseDate": day, "slot": slot,
        "classification": "analysis" if analysis else "confirmed",
        "isSensitive": sensitive,
        "titleAr": "عنوان " + slot, "titleEn": "Title " + slot,
        "summaryAr": "ملخص " + slot, "summaryEn": "Summary " + slot,
        "detailsAr": "تفاصيل", "detailsEn": "Details",
        "evidenceAr": "الدليل", "evidenceEn": "Evidence text",
        "sourceName": "Test Source", "sourceUrl": "https://example.com/report",
        "verifiedAt": verified, "stockId": stock,
    }


def publish_full(slot, day, **kw):
    """create → submit → (review) → approve → publish, each by the right person."""
    s, it = call("POST", "/pulse-admin/items", editor["token"], item_body(slot, day, **kw))
    if s not in (200, 201):
        return None, f"create {s} {it}"
    iid = it["id"]
    steps = [("submit", editor)]
    if kw.get("sensitive"):
        steps.append(("review", reviewer))
    steps += [("approve", approver), ("publish", approver)]
    for action, who in steps:
        s, b = call("POST", f"/pulse-admin/items/{iid}/{action}", who["token"], {})
        if s != 200:
            return None, f"{action} {s} {b}"
    return iid, ""


stock_raw = sql("SELECT id FROM stocks ORDER BY id LIMIT 1")
stock_id = int(stock_raw) if stock_raw else None

ids = {}
for slot, extra in [("global", {}), ("gulf", {"analysis": True}),
                    ("sharia", {"sensitive": True}), ("opportunity", {"stock": stock_id})]:
    iid, err = publish_full(slot, DAY + "10", **extra)
    ids[slot] = iid
    check(f"8 cycle: {slot} goes draft→review→approved→published", iid, err)
if not all(ids.values()):
    sys.exit("cannot continue: a base item failed to publish")

# ─── Public reads ─────────────────────────────────────────────────────────
s, day = call("GET", "/pulse/days/" + DAY + "10", reader["token"])
items = day.get("items", []) if s == 200 else []
check("1 four daily items appear", s == 200 and {i["slot"] for i in items} == {"global", "gulf", "sharia", "opportunity"}, str(s))
check("1 anonymous users cannot read Pulse", call("GET", "/pulse/days/" + DAY + "10")[0] == 401)

s, detail = call("GET", f"/pulse/items/{ids['global']}", reader["token"])
check("2 item detail opens", s == 200 and detail.get("id") == ids["global"])
check("3 source, evidence and verification time shown",
      detail.get("sourceName") and detail.get("evidenceEn") and detail.get("verifiedAt"), str(detail)[:150])
cls = {i["slot"]: i["classification"] for i in items}
check("4 confirmed vs analysis distinguished", cls.get("global") == "confirmed" and cls.get("gulf") == "analysis", str(cls))

s1, _ = call("POST", f"/pulse/items/{ids['global']}/save", reader["token"])
s, saved = call("GET", "/pulse/saved", reader["token"])
check("5 save works and appears in Saved", s1 == 200 and any(i["id"] == ids["global"] for i in saved.get("items", [])))
check("5 share event is recorded", call("POST", "/pulse/events", reader["token"], {"event": "share", "itemId": ids["global"]})[0] == 200)
call("DELETE", f"/pulse/items/{ids['global']}/save", reader["token"])
s, saved = call("GET", "/pulse/saved", reader["token"])
check("5 unsave works", not any(i["id"] == ids["global"] for i in saved.get("items", [])))

if stock_id:
    opp = next((i for i in items if i["slot"] == "opportunity"), {})
    check("6 stock link is present on the item", bool(opp.get("stock")), str(opp.get("stock")))
else:
    check("6 stock link (staging DB has no stocks: NOT verifiable here)", False, "no stocks to link")

# ─── Drafts, roles ────────────────────────────────────────────────────────
s, d = call("POST", "/pulse-admin/items", editor["token"], item_body("global", DAY + "11"))
draft_id = d.get("id")
check("7 drafts can be created", s in (200, 201) and d.get("status") == "draft")
check("7 drafts are NOT visible to readers", call("GET", f"/pulse/items/{draft_id}", reader["token"])[0] == 404)
s, arch = call("GET", "/pulse/archive?q=Title", reader["token"])
check("7 drafts are NOT in the archive", all(i["id"] != draft_id for i in arch.get("items", [])))

call("POST", f"/pulse-admin/items/{draft_id}/submit", editor["token"], {})
check("9 the author cannot approve own item", call("POST", f"/pulse-admin/items/{draft_id}/approve", editor["token"], {})[0] in (403, 409))
check("9 a plain user cannot reach the CMS", call("GET", "/pulse-admin/items", reader["token"])[0] in (401, 403))
check("9 a reviewer cannot publish", call("POST", f"/pulse-admin/items/{draft_id}/publish", reviewer["token"], {})[0] in (403, 409))
s, b = call("POST", f"/pulse-admin/items/{draft_id}/reject", reviewer["token"], {})
check("8 reject needs a note", s in (400, 422), str(s))
s, b = call("POST", f"/pulse-admin/items/{draft_id}/reject", reviewer["token"], {"note": "needs a clearer source"})
check("8 reject with a note returns it to draft", s == 200 and b.get("status") == "draft", f"{s} {b}")

# A sensitive item's reviewer cannot also approve it.
s, sens = call("POST", "/pulse-admin/items", editor["token"], item_body("sharia", DAY + "13", sensitive=True))
sens_id = sens.get("id")
call("POST", f"/pulse-admin/items/{sens_id}/submit", editor["token"], {})
call("POST", f"/pulse-admin/items/{sens_id}/review", admin["token"], {})
check("9 the reviewer of a sensitive item cannot approve it",
      call("POST", f"/pulse-admin/items/{sens_id}/approve", admin["token"], {})[0] == 403)
check("9 a different approver can approve it",
      call("POST", f"/pulse-admin/items/{sens_id}/approve", approver["token"], {})[0] == 200)

# ─── Scheduled publishing ─────────────────────────────────────────────────
s, d = call("POST", "/pulse-admin/items", editor["token"], item_body("opportunity", DAY + "12"))
sched_id = d.get("id")
call("POST", f"/pulse-admin/items/{sched_id}/submit", editor["token"], {})
call("POST", f"/pulse-admin/items/{sched_id}/approve", approver["token"], {})
soon = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 90))
s, b = call("POST", f"/pulse-admin/items/{sched_id}/schedule", approver["token"], {"publishAt": soon})
check("10 scheduling works", s == 200 and b.get("status") == "scheduled", f"{s} {b}")
past = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60))
check("10 a past time is refused", call("POST", f"/pulse-admin/items/{sched_id}/schedule", approver["token"], {"publishAt": past})[0] in (400, 409, 422))
print("   …waiting for the scheduler to publish the scheduled item (up to 4 min)")
published = False
for _ in range(24):
    time.sleep(10)
    s, b = call("GET", f"/pulse-admin/items/{sched_id}", admin["token"])
    if b.get("status") == "published":
        published = True
        break
check("10 the scheduler publishes the scheduled item", published)

# ─── Archive, versions, change log ────────────────────────────────────────
s, arch = call("GET", f"/pulse/archive?from={DAY}10&to={DAY}12", reader["token"])
check("11 archive lists published days", s == 200 and len(arch.get("items", [])) >= 4)
s, arch2 = call("GET", "/pulse/archive?q=Title%20gulf", reader["token"])
check("11 archive search works", s == 200 and any(i["id"] == ids["gulf"] for i in arch2.get("items", [])))
s, arch3 = call("GET", "/pulse/archive?to=2999-01-01&q=Title", reader["token"])
today = time.strftime("%Y-%m-%d", time.gmtime(time.time() + 3 * 3600))
check("11 archive never shows future days", s == 200 and all(i["date"] <= today for i in arch3.get("items", [])))
fut = call("POST", "/pulse-admin/items", editor["token"], item_body("gulf", "2999-01-01"))[1].get("id")
call("POST", f"/pulse-admin/items/{fut}/submit", editor["token"], {})
call("POST", f"/pulse-admin/items/{fut}/approve", approver["token"], {})
check("11 a future-dated item cannot be published early",
      call("POST", f"/pulse-admin/items/{fut}/publish", approver["token"], {})[0] in (400, 409, 422))

gid = ids["global"]
fixed = item_body("global", DAY + "10") | {"titleEn": "Title global (fixed)"}
s, c = call("POST", f"/pulse-admin/items/{gid}/correct", approver["token"], {"kind": "corrected", "note": "fixed the figure", "item": fixed})
check("13 a correction is only PROPOSED (202)", s == 202, f"{s} {c}")
s, live = call("GET", f"/pulse/items/{gid}", reader["token"])
check("13 the live item is unchanged until a second person applies it", live.get("titleEn") == "Title global", str(live.get("titleEn")))
check("13 the proposer cannot apply their own correction",
      call("POST", f"/pulse-admin/items/{gid}/correction/approve", approver["token"], {})[0] == 403)
check("13 an editor cannot apply a correction",
      call("POST", f"/pulse-admin/items/{gid}/correction/approve", editor["token"], {})[0] == 403)
check("13 a correction without a note is refused",
      call("POST", f"/pulse-admin/items/{gid}/correct", admin["token"], {"kind": "corrected", "note": "", "item": fixed})[0] in (400, 422))
s, c = call("POST", f"/pulse-admin/items/{gid}/correction/approve", admin["token"], {"note": "checked"})
check("13 a different approver applies the correction", s == 200, f"{s} {c}")
s, vers = call("GET", f"/pulse-admin/items/{gid}/versions", admin["token"])
vlist = vers if isinstance(vers, list) else vers.get("versions", [])
check("12 previous versions are kept", s == 200 and len(vlist) >= 1, str(vers)[:100])
s, ev = call("GET", f"/pulse-admin/items/{gid}/events", admin["token"])
elist = ev if isinstance(ev, list) else ev.get("events", [])
check("13 every change is in the change log", s == 200 and len(elist) >= 4, str(len(elist)))
s, pub = call("GET", f"/pulse/items/{gid}", reader["token"])
check("13 readers see the corrected title and marker", pub.get("titleEn") == "Title global (fixed)" and pub.get("changeKind") == "corrected", str({k: pub.get(k) for k in ("titleEn", "changeKind", "marker")}))

# ─── Settings, analytics, bilingual ───────────────────────────────────────
s2, _ = call("PATCH", "/me/notification-prefs", reader["token"], {"pulseNewEnabled": False})
s3, prefs = call("GET", "/me/notification-prefs", reader["token"])
flat = prefs.get("prefs", prefs) if isinstance(prefs, dict) else {}
check("15 user Pulse notification settings save", s2 == 200 and flat.get("pulseNewEnabled") is False, f"{s2} {prefs}"[:160])
call("POST", "/pulse/events", reader["token"], {"event": "open_item", "itemId": ids["gulf"]})
call("POST", "/pulse/events", reader2["token"], {"event": "open_item", "itemId": ids["gulf"]})
call("POST", "/pulse/events", reader2["token"], {"event": "view_day"})
s, an = call("GET", f"/pulse-admin/analytics?from={today}&to={today}", admin["token"])
check("16 basic analytics are recorded and shown (events counted by the day they happen)", s == 200 and an.get("itemOpens", 0) >= 2 and an.get("dayViews", 0) >= 1, str(an)[:150])
check("16 an event for a draft id is rejected (no existence leak)",
      call("POST", "/pulse/events", reader["token"], {"event": "open_item", "itemId": draft_id})[0] == 404)
first = items[0] if items else {}
check("17 content exists in Arabic and English", bool(first.get("titleAr")) and bool(first.get("titleEn")))

failed = [n for n, ok in RESULTS if not ok]
print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} checks passed")
for n in failed:
    print("  FAILED:", n)
sys.exit(1 if failed else 0)
