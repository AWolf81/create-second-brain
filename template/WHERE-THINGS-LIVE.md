# Where things live

Read this before writing anything into this vault. It answers two questions: which
system is authoritative for a given kind of information, and whether a fact you just
learned belongs here at all.

Replace the `<angle brackets>` with your own tools. Delete rows that do not apply.

## Systems of record

Each domain has exactly one authority. Read from it; do not copy it here.

| Domain | Authority | Read via | Never copy into |
|---|---|---|---|
| Raw capture, dated tasks | `<your tracker>` | its API or MCP server | knowledge notes |
| Specs, plans, `file:line` findings | `<your product repo>` | git | this vault |
| Durable lessons | **this vault** | `05-knowledge/` | the product repo |
| Project status and orientation | **this vault** | `04-projects/<name>/` | anywhere else |
| Decisions and their rationale | `<wherever you record decisions>` | | |

When a note needs to point at implementation detail, **link to the path in its own
repository** rather than copying it. Copies rot; the source does not.

## Instance fact or business fact?

The only classification that matters, applied to every fact before you write it down.

| | Instance fact | Business fact |
|---|---|---|
| Example | "Activation is scoring-completed within 7 days of signup" | "Anchor activation on the earliest reliable server-side event, bounded by a window" |
| Names a specific product? | yes | no |
| Still true in a year, elsewhere? | maybe | yes |
| Belongs in | the spec or plan, in the product repo | `05-knowledge/` |

**The test is mechanical.** Remove the product name. If the sentence becomes false or
empty, it is an instance fact and does not belong here. If it still stands on its own,
it is a business fact and it does.

The corollary people get wrong: a business fact is usually *shorter* than the instance
fact it came from. If your knowledge note is longer than the plan it was harvested from,
you copied instead of extracting.

## The promotion rule — one direction only

```
<product repo>  ──  harvest  ──▶  05-knowledge/
   the specifics                  the sentence that transfers
```

Specifics stay where they were written. The transferable sentence moves. Nothing flows
back: this vault never becomes the place plans are written.

## Rules of engagement

- **Harvesting is read-only on the source.** Never complete, close or delete a task,
  ticket or issue as a side effect of harvesting it. Say it was absorbed and let a human
  close it.
- **Tasks that outlive the session go to `<your tracker>`.** An agent's in-session task
  list is scratch. Do not invent `TODO.md` files — they rot the moment the session ends.
- **A title alone is rarely worth a note.** The description, the thread or the diff is
  the payload.
- **Record where a fact came from**, so it can be re-checked later:

  ```
  [Source: <where> | YYYY-MM-DD | confidence: high|medium|low]
  ```

  Confidence is about the claim's durability, not your writing. `high` — decided and
  acted on, or verified. `medium` — decided in principle, not yet executed. `low` — a
  working assumption. Anything legal, tax or regulatory is `medium` at best unless a
  professional or an official document confirmed it.

## Note titles

Every note opens with a single `# Heading`. The site derives its page title, graph label
and search entry from it, and `./scripts/validate-note-titles.sh` fails the build if one
is missing. Long headings are shortened for the graph; override with frontmatter
`title:` when that reads badly.
