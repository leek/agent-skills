# Special Case

`Within · Change Preventers · Conditional Logic`

A routine that does one job carries a branch for "the one weird case", a
complex `if`, or a value check performed before the actual work begins. It
usually starts as a hotfix: a single customer, a legacy import, a record type
that arrives in the wrong shape, handled inline because the deadline was
yesterday. It is never revisited, so from then on every reader has to hold the
exception in their head alongside the rule, and cannot tell which parts of the
body belong to the general algorithm and which exist only for the exception.
The cost compounds in tests, where the special case needs its own bespoke
fixture and its own assertion, and in change, because the next exception is
cheapest to add as a sibling branch. Values that only the exceptional path
populates become [Temporary Field](temporary-field.md)s on the surrounding
object. [Null Check](null-check.md) is the most familiar member of this family
: absence is just the special case everyone writes. Recursion is the honest
exception: a base case is a special case that genuinely belongs.

## Detection heuristics

### Agnostic

- The first block of a method handles a case named after a customer, tenant,
  vendor, legacy import, or date cutoff, and the rest of the body is the
  general algorithm.
- The condition tests something specific rather than categorical, a hardcoded
  id, slug, email address, or magic string
  ([Magic Number](magic-number.md)).
- Variables assigned inside the exceptional branch are meaningless in the
  general path but still declared alongside it
  ([Temporary Field](temporary-field.md)).
- Checking and massaging values consumes the top of the method before any real
  work happens
  ([Required Setup or Teardown Code](required-setup-or-teardown-code.md)).
- Exactly one test targets the branch, it is the only test needing a hand-built
  fixture, and its name repeats the exception rather than describing a rule.
- The branch arrived in a commit that says "hotfix" or "temporary", nothing has
  touched it since, and nobody can say whether the triggering scenario still
  exists.

### PHP / Laravel

- Action or service classes opening with a branch for one tenant or plan, 
  `if ($team->slug === 'founder-plan')`: ahead of the logic every other team
  runs through.
- Eloquent accessors, scopes, and observers that test hardcoded keys
  (`if ($this->id === 1)`) instead of a column, cast, or policy that expresses
  the rule.
- A `type` column switched on inside one model, where per-type action classes
  or child models would carry their own behaviour.
- Blade partials with an `@if ($order->type === 'refund')` block inside
  otherwise shared markup, instead of `@include`ing a type-specific partial or
  passing a per-type view model.
- Laravel Pennant flags (`Feature::active('new-checkout')`) that outlived their
  rollout, so the conditional now permanently selects one path and the other
  branch is [Dead Code](dead-code.md).

### TS / React

- A component that returns a different tree before its main `return` based on
  one prop value (`if (variant === 'legacy') return <LegacyTable />`); that is
  two components behind one export.
- Reducers or state machines that handle one action outside the `switch`,
  usually just above it.
- Hooks with an early return keyed to a specific route or id
  (`if (pathname === '/checkout') return fallback`), so the hook's contract
  differs per page.
- API adapters with a per-vendor `if` in front of otherwise generic mapping, 
  one adapter per vendor behind a shared interface removes it.
- Experiment or feature-flag branches (`if (flags.newPricing)`) left in place
  after the experiment concluded.

## Example

Translated from the upstream Python example, which shows only the smelly
half; the solution is authored for this card.

Smelly; one import source is handled inline, ahead of the parse everything
else uses:

```ts
function parseOrder(payload: OrderPayload): Order {
  if (payload.source === 'legacy-import') {
    const legacyLines = payload.lines.map(normaliseLegacyLine);

    return {
      ...baseOrder(payload),
      lines: legacyLines,
      totalCents: sumLines(legacyLines),
    };
  }

  const lines = payload.lines.map(normaliseLine);

  return { ...baseOrder(payload), lines, totalCents: sumLines(lines) };
}
```

Solution: each source owns its parsing behind a shared interface, so the
entry point holds no exceptions:

```ts
interface OrderParser {
  parse(payload: OrderPayload): Order;
}

const parsers: Record<OrderSource, OrderParser> = {
  'legacy-import': legacyOrderParser,
  api: apiOrderParser,
  manual: manualOrderParser,
};

function parseOrder(payload: OrderPayload): Order {
  return parsers[payload.source].parse(payload);
}
```

When the exceptional path is genuinely small, consolidating the condition into
one named predicate is enough: polymorphism is worth it once the branch has
its own body, its own fields, or its own tests.

## Refactorings

- Consolidate Conditional Expression
- Replace Conditional with Polymorphism
- Introduce Null Object
- Replace Exception with Test

## Related smells

| Smell | Edge |
|---|---|
| [Null Check](null-check.md) | family |
| [Temporary Field](temporary-field.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Complex Conditional

---

*Derivative work adapted from "Special Case" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
