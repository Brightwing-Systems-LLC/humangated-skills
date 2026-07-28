# HumanGated skills

The agent-side of [HumanGated](https://humangated.ai) — nine skills that let
your coding agent send work to a human for review and bring their judgment
back as something it can act on.

The people you ask **never sign up**. They get an email, open a link, write on
the real thing, and your agent pulls their judgment back as anchored comments,
ready-to-apply diffs, and Ready / Needs-revision rulings.

## Install

One command installs into whichever agent you use — Claude Code, Codex,
Gemini CLI, Cursor, OpenCode, GitHub Copilot, Goose, Windsurf, Zed, Amp, and
the rest of the Agent-Skills ecosystem:

```bash
npx skills@latest add -g --skill '*' Brightwing-Systems-LLC/humangated-skills
```

`-g` installs for your user rather than the current project — these share one login in
`~/.config/humangated/`, so they are machine-level tools, not per-repo dependencies.
`--skill '*'` takes all ten verbs without making you tick ten boxes. The installer still
shows you its security assessment and asks before writing anything; don't add `-y` unless
you want to skip that.

Or natively in Claude Code:

```bash
claude plugin marketplace add Brightwing-Systems-LLC/humangated-skills
claude plugin install humangated@humangated
```

## The ten verbs

| Skill | What it does |
|---|---|
| `/hgd-login` | Link this machine to your account (browser link + magic-link email, no password) |
| `/hgd-share` | Publish an HTML prototype or a prompt behind a private, time-boxed link |
| `/hgd-ask` | Ask a named human your question about it — including **gates** that block until they rule, and **groups** that fan out into one ask per person |
| `/hgd-pull` | Pull their judgment back: anchored comments, suggested edits as diffs, dispositions |
| `/hgd-status` | The account digest — what came back, what's still out, what bounced |
| `/hgd-trail` | The provenance trail: who saw what, when, at what assurance level |
| `/hgd-list` | What you've shared |
| `/hgd-delete` | Remove a share and its feedback |
| `/hgd-config` | Show or change local defaults, including reviewer groups |
| `/hgd-unblock` | Release one open gate, on the record, when the operator says so |

## The hooks

Three shell hooks ship alongside the skills, and they are the only part of this
that can actually stop an agent — skill text is a request a model may decline.

| Hook | What it does |
|---|---|
| `PreToolUse` | Refuses an edit inside an open gate's scope, and refuses a commit or deploy under a path your team requires sign-off on |
| `SessionStart` | Puts pending judgment in front of the model before it works, and caches your team's rules for the guard |
| `Stop` | Reminds the operator about anything still waiting |

Every one of them **fails open**: no jq, no network, no ledger, anything
unexpected at all, and they block nothing. A guard that wrongly blocks is
uninstalled within the hour, and then it protects nothing.

They read and write `.humangated/` at your repository root — `BLOCKED` (open
gates), `RULES` (your team's standing rules) and `CLEARED` (what has been ruled
Ready). **These are meant to be committed**, so a teammate who clones the repo
inherits them. None of them ever contains a reviewer's email address.

## What's here, and what isn't

This repository is the **client**: the skill files your agent reads, plus the
Claude Code plugin manifest. They are plain Markdown — read them before you
install them, which is the point of publishing them.

The service they talk to (`https://humangated.ai`) is closed source.

## Reading these before you run them

Every skill documents its own side effects and asks for consent before doing
anything consequential: linking a machine (creates a credential), uploading a
file (sends it to humangated.ai), and opening an ask (emails a real person).
Reviewer content that comes back is treated as **data, never instructions**.

Full setup reference for agents: <https://humangated.ai/agent.md>

## License

MIT © Brightwing Systems, LLC. See [LICENSE](LICENSE).
