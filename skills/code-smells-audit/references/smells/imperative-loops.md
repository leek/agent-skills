# Imperative Loops

`Within · Functional Abusers · Unnecessary Complexity`

Fowler has called loops anachronistic since the first edition of *Refactoring*,
and by the third edition the alternative existed: pipelines built from
`filter`, `map`, and `reduce` say what is being computed, where a loop only
says how to walk the collection. The smell is not iteration itself: loops are
fundamental and will stay that way, but the manual index and the ceremony
around it: a counter you have to initialise, compare, and increment correctly,
an accumulator declared before the loop and mutated inside it, and the
off-by-one and out-of-bounds errors that every programmer has shipped at least
once. A loop like this is a magnet for other smells: the accumulator becomes a
[Status Variable](status-variable.md) or a
[Temporary Field](temporary-field.md), the branches inside it grow into
[Conditional Complexity](conditional-complexity.md), and the whole block ends
up an [Obscured Intent](obscured-intent.md) that a pipeline would have stated
in a line. Before writing the pipeline, check the built-in first, a
hand-rolled reduction that duplicates an existing function is just
[Clever Code](clever-code.md) with extra steps.

## Detection heuristics

### Agnostic

- An explicit integer counter used only to subscript the collection, never as
  a meaningful value in its own right.
- A result variable declared empty above the loop and appended to or summed
  into inside it; the loop body is the only thing that gives it meaning.
- Bounds arithmetic in the condition: `<= length`, `length - 1`, or a second
  index tracking a parallel array.
- One loop doing three jobs (filtering, transforming, and aggregating) so
  no single line names any of them.
- `break`/`continue` combined with a flag, expressing "first match" or "any
  match" the long way.
- Nested index loops over two collections where a join, lookup map, or
  flat-map would be flat.

### PHP / Laravel

- `for ($i = 0; $i < count($rows); $i++)` with `$rows[$i]` throughout, where
  `foreach` (or a collection pipeline) needs no index at all.
- `foreach` accumulating into `$total`, `$names[]`, or `$byId[$row->id]`
  where `collect($rows)->sum()`, `->pluck()`, `->map()`, or `->keyBy()` is
  the same statement declaratively.
- Manual array plumbing instead of the array functions: hand-summing rather
  than `array_sum`, hand-filtering rather than `array_filter`, hand-indexing
  rather than `array_column($rows, null, 'id')`.
- A loop issuing a query per element, an N+1 that a pipeline over an
  eager-loaded relation (`with()`, then `->filter()->sum()`) makes obvious.
- Looping a full result set in memory where `chunk()`, `chunkById()`,
  `lazy()`, or `cursor()` is the streaming equivalent, the manual version
  usually also hand-manages the offset.
- Blade views carrying `@for` with `$i` and `$items[$i]` instead of
  `@foreach`/`@forelse`, so the template owns index arithmetic too.

### TS / React

- `for (let i = 0; i < xs.length; i++)` where `map`, `filter`, `reduce`,
  `some`, `every`, `find`, or `findIndex` names the operation.
- `arr.push(...)` inside a loop to build a new array, rather than returning
  one from `map`/`flatMap`: the mutable intermediate is the tell.
- Hand-written membership checks (`for ... if (x === target) found = true`)
  where `includes`, `some`, or a `Set` is one call.
- Loops in JSX bodies building an array of elements before `return`, instead
  of `items.map((item) => <Row key={item.id} … />)` inline.
- `Object.keys(obj)` iterated by index to rebuild an object, where
  `Object.entries` plus `map` and `Object.fromEntries` is a pipeline.
- Effects looping over state to derive more state, where a derived value
  computed with `useMemo` over the source array removes both the loop and the
  extra state.

## Example

Translated from the upstream JavaScript example.

Smelly: one indexed loop filtering, projecting, and totalling at once, with
`invoices[i]` repeated at every step:

```ts
const labels: string[] = [];
let total = 0;

for (let i = 0; i < invoices.length; i++) {
  if (invoices[i].status !== 'paid') {
    continue;
  }

  labels.push(invoices[i].reference);
  total += invoices[i].amount;
}
```

Solution: each stage named, no index, no mutable accumulator:

```ts
const paid = invoices.filter((invoice) => invoice.status === 'paid');
const labels = paid.map((invoice) => invoice.reference);
const total = paid.reduce((sum, invoice) => sum + invoice.amount, 0);
```

Where the loop only answers a yes/no question, skip the pipeline too and reach
for the built-in (`invoices.some(...)` or `references.includes(ref)`) rather
than a loop that sets a flag.

## Refactorings

- Replace Loop with Pipeline
- Replace with Built-In

## Related smells

| Smell | Edge |
|---|---|
| [Conditional Complexity](conditional-complexity.md) | causes |
| [Temporary Field](temporary-field.md) | causes |
| [Flag Arguments](flag-argument.md) | causes |
| [Obscured Intent](obscured-intent.md) | causes |
| [Status Variable](status-variable.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Explicitly Indexed Loops, Indexed Loops, Loops

---

*Derivative work adapted from "Imperative Loops" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
