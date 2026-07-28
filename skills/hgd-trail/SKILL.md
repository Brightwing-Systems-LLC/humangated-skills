---
name: hgd-trail
description: Use when the operator wants the history of who touched something — "give me the activity trail for this prompt", "everything Mike has done", "who reviewed the checkout mockup", "did my ask email even get delivered?". Pulls the provenance/activity log for any dimension (artifact, request, reviewer, action, time window) and renders an aligned timeline. Can then compose a Markdown or PDF report on request.
---

Read the append-only activity log sliced by whatever the operator anchored on, and
render a compact aligned timeline plus a one-line rollup. It is **provenance /
attribution — "who touched this and what happened" — not a certified audit**, and the
render says so.

## Step 1 — Config

```bash
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/humangated"
HGD_SKILLS_VERSION=4.5.1
[ -n "$HGD_TOKEN" ] || . "$CFG/config" 2>/dev/null
```

## Step 2 — Query (pick the subject from what the operator anchored on)

```bash
curl -s "$HGD_BASE_URL/api/activity?subject=artifact:<uuid>" \
  -H "Authorization: Bearer $HGD_TOKEN" -H "X-HumanGated-Skills: $HGD_SKILLS_VERSION"
```

Subjects: `artifact:<uuid>` (everyone who touched this thing) ·
`request:<uuid>` (one ask, end to end — including its email_delivered/bounced fate) ·
`reviewer:<email>` (everything that person has done). No subject = everything you own.
Extra filters: `&actor=<email>` `&action=<name>` `&since=<iso>` `&until=<iso>` `&limit=`.

The payload: `{label, count, truncated, actors[], actions{}, span, events[]}` — each
event carries `ts, actor, actor_kind, assurance, action, artifact, version, detail`.

## Step 3 — Render (keep this exact shape)

```
**Activity — {subject label}** · {count} events · {N} actors · {date span}

​```
{HH:MM}  {actor:<22} {action:<20} {target/context}   {assurance}
…one line per event, newest first, columns padded by YOU…
​```
_Provenance / attribution — not a certified audit. Reviewer identity is flagged
asserted / vouched / verified on every event._
```

- The timeline goes inside a plain fenced block so alignment survives (Markdown won't
  reflow it). Pad the columns yourself; keep lines ≤ ~90 chars.
- Newest first; cap ~20 rows on screen and say "+ N older — want the full report?".
- Honor the honesty flags: show each row's `assurance`; never present an `asserted`
  actor as proven. `email_delivered` / `email_bounced` rows answer "did the ask land?" —
  on a bounce, suggest the hand link from `hgd-ask`.

## Step 4 — Offer a report

> Want this as a Markdown or PDF document to share? I'll shape the full log into one.

If yes: re-query with a higher `limit`, and YOU compose the document from `events[]`
(the service returns data; the agent makes the document). Always carry the
"provenance, not a certified audit" line into the document header.

## Guardrails

- Never dump raw JSON at the operator; the fenced timeline is the surface.
- Never upgrade the claim: this is attribution, not compliance evidence. If asked
  "is this audit-grade?", say plainly it's an activity log with flagged identity
  assurance, and that per-item email verification is the current step up.
