# Callback Hell

`Within · Change Preventers · Conditional Logic`

A callback is a function handed to another function to be run later, and one
of them is harmless. The smell is the staircase: each callback opens the next,
so the sequence of steps is encoded as nesting depth and the work that matters
sits four or five indents from the margin, under a cascade of closing
brackets. Two things go wrong at once. The reader has to hold every enclosing
scope in their head to understand the innermost line, which is the same
comprehension tax as
[Conditional Complexity](conditional-complexity.md) — the sibling this smell
is usually found next to. And control inverts: the caller no longer decides
when, whether, or how often its continuation runs, because it handed that
decision to whatever it passed the function into. Nesting also hides
concurrency, since steps that never depended on each other end up serialised
purely because one was written inside the other. Promises, `async`/`await`,
and pulling each level out into a named function all dissolve the staircase;
which one you reach for depends on how much of the API you control.

## Detection heuristics

### Agnostic

- Three or more anonymous functions nested inside one another, with the
  closing punctuation stacking into a cascade at the bottom.
- The operative statement is at indentation level four or deeper, while the
  enclosing lines are pure plumbing.
- The same error branch is re-written at every level (`if (err) return
  cb(err)`), because there is no single place errors can surface.
- Steps that share no data are still nested, so they run one after another
  when they could have run together.
- None of the intermediate steps has a name — the sequence can only be
  described by reading it, not by listing it.
- A value from level one is still in scope at level four, so the innermost
  callback silently depends on everything above it.

### PHP / Laravel

- `Bus::batch([...])->then(...)->catch(...)->finally(...)` where a callback
  dispatches another batch with its own callbacks, so the workflow's shape
  lives in closure nesting instead of in `Bus::chain()` or a job class.
- `DB::transaction(function () { ... })` wrapping
  `Model::withoutEvents(function () { ... })` wrapping a
  `->each(function () { ... })` — three closures deep before the first write.
- `Http::pool(function (Pool $pool) { ... })` whose response handling opens
  further Guzzle `->then(function ($response) { ... })` callbacks per request.
- Model event hooks registered from inside other closures — a
  `static::created(function (Order $order) { ... })` inside `booted()` that
  itself registers listeners conditionally.
- `Validator::make($data, $rules)->after(function ($validator) { ... })`
  containing closure rules
  (`function (string $attribute, mixed $value, Closure $fail)`) that open
  further closures per field.

### TS / React

- Node-style `(err, result) => { ... }` callbacks nested three deep where the
  promise API (`fs/promises`, `util.promisify`) exists and is unused.
- `.then((res) => { fetch(...).then(...) })` — promises nested rather than
  returned and chained, so the middle value is captured by closure scope
  instead of flowing through.
- A chain of `useEffect` hooks coupled by state flags, each effect existing
  only to fire once the previous one has set its piece of state.
- Mutation handlers nesting handlers: `useMutation({ onSuccess: () =>
  other.mutate(input, { onSuccess: () => ... }) })`.
- `setTimeout` inside `setTimeout`, or an `addEventListener` handler that
  registers further listeners, to express "then do this next".

## Example

Translated from the upstream JavaScript example.

Smelly — four steps, four indent levels, and `bread` is still in scope at the
bottom:

```ts
const makeSandwich = (): void => {
  getBread((bread) => {
    sliceBread(bread, (slices) => {
      getJam((jam) => {
        brushBread(slices, jam, (smeared) => {
          serve(smeared);
        });
      });
    });
  });
};
```

Solution — each step returns a promise, so the sequence reads top to bottom
and the two independent steps can finally run at the same time:

```ts
const getBread = (): Promise<Bread> => { /* ... */ };
const sliceBread = (bread: Bread): Promise<Slice[]> => { /* ... */ };
const getJam = (): Promise<Jam> => { /* ... */ };
const brushBread = (slices: Slice[], jam: Jam): Promise<Sandwich> => { /* ... */ };

const makeSandwich = async (): Promise<Sandwich> => {
  const bread = await getBread();
  const [slices, jam] = await Promise.all([sliceBread(bread), getJam()]);

  return brushBread(slices, jam);
};
```

Note what the flattening exposed: fetching the jam never needed the bread, a
fact the staircase had buried.

## Refactorings

- Extract Method
- Use Asynchronous Functions
- Use Promises

## Related smells

| Smell | Edge |
|---|---|
| [Conditional Complexity](conditional-complexity.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Hierarchy of Callbacks, Pyramid of Doom

---

*Derivative work adapted from "Callback Hell" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
