# Knowledge

Durable notes. A note earns its place here if a future, unrelated project could
use it.

Each note answers: what was decided, **what it was decided against**, and why.
The rejected option is usually the more valuable half — it is the one you will
otherwise reach for again.

## Conventions

Open every note with a single `# Heading`. The site derives its title and graph
label from that; long headings are shortened at the first dash, colon or comma,
so `# Metrics, activation, and instrumentation` labels as *Metrics*. Override
with frontmatter when the result reads badly:

```markdown
---
title: "Short label"
---

# A much longer heading that would truncate awkwardly
```

Attribute facts inline so a claim can be re-checked later:

```
[Source: <where> | YYYY-MM-DD | confidence: high|medium|low]
```

## Route the question

Keep this table current as notes are added. It is the reason an agent reads the two
notes that answer a question instead of reading this page and then guessing — the
difference matters from about a dozen notes onward, and by fifty it is the whole
game.

Route on the **question a reader arrives with**, not on the note's topic. "What do we
charge for the second seat" is the question; "pricing" is the filing.

| If the question is about… | Read |
|---|---|
| _the shape of question you actually get asked_ | [`note-name`](note-name.md) |

Add a second table for questions that span notes. Those get answered wrongly most
often, because each note alone looks complete.

## When nothing matches

**Say so, then answer from general knowledge — labelled as such.**

Do not fill the gap quietly. The value of this vault is that it records decisions taken
*against* the obvious default; an answer that reaches for the default without saying so
is indistinguishable from a grounded one, and worse. The same applies to a partial
match: name which half is grounded and which is not.
