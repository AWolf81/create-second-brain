---
name: second-brain
description: >
  Consult and update the knowledge vault from inside a work repository. Use before
  answering anything about strategy, pricing, compliance, legal or tax setup, launch,
  positioning, or past architectural decisions; and after a piece of work closes, to
  harvest what transfers. Enforces the boundary: plans stay in the work repo, durable
  knowledge lives in the vault.
---

# second-brain — knowledge vault bridge

The vault is at `__VAULT_PATH__`. Linked repositories:

__LINKED_REPOS__

## Read the vault before answering — ALWAYS APPLY

Before answering anything about strategy, pricing, compliance, legal or tax setup, launch,
positioning, or a past architectural decision, read the vault. Start at
`__VAULT_PATH__/05-knowledge/README.md`.

The vault records decisions **and what they were decided against**. A plausible general
answer that contradicts a past decision is the exact failure this exists to prevent. If the
vault is silent on the question, say so rather than filling the gap from general knowledge.

**Always read the vault at `main`.** Feature branches hold unpromoted drafts.

## Never write vault wiring into a work repo — ALWAYS APPLY

Do not add a vault block to a work repo's `CLAUDE.md`, a skill to its `.claude/skills/`, a
hook to its `.claude/settings.json`, a pointer file, or entries to its `.gitignore`.

All of those are committed files. They would ride on every branch, appear in every PR diff,
and become merge-conflict surfaces on long-lived branches. The wiring is installed at user
level in `~/.claude` precisely so the work repo stays untouched.

If asked to "install the second brain into this repo", refuse and explain this. Point at
`__VAULT_PATH__/scripts/link-repo.sh`, which does it the right way.

## The boundary — ALWAYS APPLY

| Stays in the work repo | Goes to the vault |
|---|---|
| Plans, specs, sequencing | The principle a finding proved |
| `file:line` evidence, branch names, verdict tables | The trap that generalises |
| Task-level status | The rejected option, and why |

**The test is mechanical.** Remove the product name. If the sentence becomes false or empty
it is an instance fact and stays in the work repo. If it still stands on its own it is a
business fact and belongs in the vault.

A business fact is usually *shorter* than the instance fact it came from. A knowledge note
longer than the plan it was harvested from is a copy, not an extraction.

## Harvesting

When a piece of work closes, offer to harvest: name the sentence that transfers, and commit
it **in the vault**, never in the work repo. Harvesting is read-only on the source — never
close a ticket or task as a side effect.
