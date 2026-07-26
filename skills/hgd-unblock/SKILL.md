---
name: hgd-unblock
description: Use when the operator wants to proceed on work that an open HumanGated gate is holding — "override the gate", "I'll take responsibility, go ahead", "unblock the billing ask". Records the override and its reason in the ledger so the decision is visible, then releases the guard for that one ask. Never use this on your own initiative.
---

Release one open gate, on the record.

## Step 1 — This is the operator's call, never yours

**Do not run this because you are blocked and want to continue.** Being blocked
is the gate working. The operator told a named human their work was held; only
the operator can decide that promise no longer applies.

Run it when they say so in words — "go ahead anyway", "override it", "I'll deal
with Mike". If they merely sound impatient, offer the alternatives first: work
outside the scope, or `/hgd-status` to see whether the reviewer has answered.

## Step 2 — Ask why, once

```bash
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/humangated"
HGD_SKILLS_VERSION=3.10.0
[ -n "$HGD_TOKEN" ] || . "$CFG/config" 2>/dev/null
```

You need a reason in the operator's own words. One line is plenty ("shipping the
hotfix, will re-ask Mike after"). Don't editorialize it and don't invent one —
a blank reason makes the record worthless, which defeats the point of allowing
an override at all.

If they won't give one, say you'll record "no reason given" and do that. An
honest empty record beats a plausible fabricated one.

## Step 3 — Record it, then release it

Append to the ask's ledger entry at `.humangated/asks/<uuid>.md`:

```markdown
## Override
Unblocked <ISO-8601 timestamp> — <the operator's reason, verbatim>
The reviewer was told: <the `declared` sentence from the ledger>
```

Then remove that uuid's line from `.humangated/BLOCKED`. **Removing the line is
what releases the guard**, so both edits belong in the same commit — a ledger
that says "overridden" while BLOCKED still holds the line is a lie in one
direction, and the reverse is a lie in the other.

Leave the ask itself **open**. The human may still answer, and their answer
still matters; you have overridden the block, not withdrawn the question.

## Step 4 — Say what just happened

```
Gate released · {uuid} · {reviewer}
They were told: "{declared sentence}"
Your reason: "{reason}"
Recorded in .humangated/asks/{uuid}.md — the ask is still open.
```

Then one sentence: *"Worth telling {reviewer} directly — they're still expecting
to be the one who decides this."* Say it once; don't nag.

## What this does NOT do

- **It does not close the ask.** Use `/hgd-delete <uuid>` to withdraw it, and
  tell the reviewer if you do — someone is holding time for it.
- **It does not record a ruling.** An overridden gate has no disposition. Nobody
  approved anything, and the trail must never suggest otherwise.
- **It does not touch other gates.** One uuid, one release.

## Guardrails

- Never override a gate the operator has not named. If several are open, list
  them and ask which.
- Never remove a line from `BLOCKED` for any other reason. Only `/hgd-pull`
  (answered) and this skill (overridden) may take one out.
