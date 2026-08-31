# Skill mechanics

The skill-specific branch of [`writing-for-agents`](SKILL.md): what changes when the document is a skill: frontmatter, the invocation choice, and router skills. Everything else about writing it is the universal reference in `SKILL.md`.

## Frontmatter

```markdown
---
name: <skill-name>
description: <see the invocation choice below>
disable-model-invocation: true   # only on user-invoked flows
---
```

`name` is the folder name in `kebab-case`. `SKILL.md` is the exact filename, uppercase.

## Invocation

Two choices, trading the two loads:

- A **model-invoked** skill keeps a `description`, so the agent can fire it autonomously, and other skills can reach it. You can still type its name: model-invocation always _includes_ user reach; a description only ever adds agent discovery, never removes the human's. The description is the skill's top-level **context pointer**, forced to stay loaded at all times: permanent **context load** in exchange for discoverability. A model-invoked skill whose content is all reference is also one home for shared reference, another skill can invoke it, so reference needed by several skills lives in one place. Mechanics: omit `disable-model-invocation`, and write a model-facing description carrying the trigger branches (the pointer-writing rules in `SKILL.md` apply in full).
- A **user-invoked** skill strips the description from the agent's reach: only the human typing its name can invoke it, and no other skill can. Zero context load, but it spends **cognitive load**: you are the index that must remember it exists. Mechanics: set `disable-model-invocation: true`; the `description` becomes human-facing: a one-line summary, trigger lists stripped.

Pick model-invocation only when the agent must reach the skill on its own, or another skill must. If it only ever fires by hand, make it user-invoked and pay no context load.

The invariant that follows: **a user-invoked skill can never be reached by another skill.** A skill that tells the agent to invoke one is broken, have it recommend the flow to the human instead.

Shared reference that two user-invoked skills both need can live in neither: with no descriptions, neither can fire the other. Push it to a plain file outside the skill system, external reference any skill can point at.

## Splitting by invocation

The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a model-invoked skill when you have a distinct **leading word** that should trigger it on its own (a trigger word you actually use in your prompts) or another skill must reach it. You pay context load for the new always-loaded description, so that independent reach has to be worth it.

## Router skills

When user-invoked skills multiply past what you can remember, that piled-up cognitive load is cured by a **router skill**: one user-invoked skill that names the others and when to reach for each, so the human has one skill to remember instead of many. It can only hint, never fire them, user-invoked skills have no description, so nothing but the human can reach them.

## Portability

A skill folder is copied into whichever agent's skills directory the user runs. Name harness-specific tooling only where the skill genuinely cannot work without it, and say what the fallback is; an instruction naming a tool the running harness does not have is unfollowable, not merely unused. Prefer describing the capability ("dispatch a read-only subagent", "ask the user to choose") over naming one harness's tool for it.
