# Build ticket template

Use for each build ticket; the delivery ticket has its own template in
[DELIVERY-TICKET.md](../DELIVERY-TICKET.md).

```markdown
---
title: "<Ticket title>"
status: ready-for-agent
claimed-by:
blocked-by: []
deploy-gate: false
---

# <NN>: <Ticket title>

## Parent

Relative path to the spec (`../spec.md`), or omit on the spec-less path.

## Parent context

- [Build Contract](../spec.md#build-contract) (when a spec exists)
- [<only another spec heading this ticket needs>](../spec.md#<heading-anchor>)
- [Codebase evidence](../research/codebase.md#<relevant-heading>) (when present)

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective,
not a layer-by-layer implementation list.

## Acceptance criteria

- [ ] Behavior statements: what a user/caller can now do, what data is
      persisted, what is forbidden (authorization), never presentation
      ("page shows heading X") or implementation ("uses a repository")

## Files

- `<verified path this ticket expects to create or edit, registrations included>`

## Scheduling

Work: <1, 2, or 3; small, medium, or large relative to this effort>
<One sentence naming the likely implementation, setup, or test cost.>
```

Omit unavailable context links. On a spec-less path, carry decisions inline per the
parent skill. Keep comments out of the frontmatter: an empty `claimed-by` means
unclaimed. Blockers live in frontmatter as ticket numbers, not a body section.
