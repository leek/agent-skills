# Wide refactors

Read this in [`to-tickets`](../SKILL.md) step 3 when the work holds a wide refactor: one mechanical change (rename a column, retype a shared value object) whose blast radius fans across the codebase so no vertical slice can land green.

Sequence it as **expand–contract**:

1. **Expand**: add the new form beside the old so nothing breaks (new nullable column + dual-write; new method delegating to old).
2. **Migrate**: move call sites/data over in batches sized by blast radius (per module, per directory), each batch its own ticket blocked by the expand. A data backfill is its own ticket, a one-time operation leaving no permanent infra.
3. **Contract**: drop the old form once no caller remains, in a ticket blocked by *every* migrate batch. The contract migration is the only destructive step and lands last.

When even batches can't stay green alone, keep the sequence but share an integration branch, all blocking a final integrate-and-verify ticket: green is promised only there.
