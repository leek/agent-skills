# Status Variable

`Within · Obfuscators · Unnecessary Complexity`

A mutable primitive declared before an operation, written to during it, and
read afterwards as a switch — `$found = false` ahead of a search, `$success`
ahead of a save, `$i = 0` ahead of a loop. It is really a signal rather than a
defect of its own: wherever one appears you will usually find an
[Imperative Loop](imperative-loops.md) that caused it, plus some combination
of [Clever Code](clever-code.md), [Mutable Data](mutable-data.md),
[Afraid to Fail](afraid-to-fail.md), and a [Special Case](special-case.md)
being smuggled through the flag. The cost is that the reader can no longer
tell what a block does by looking at any one line: meaning is spread across
the initialisation, every assignment inside the body, and the check at the
end, and correctness depends on all of them agreeing. Flags also leak — once
one exists, callers start reading it, and downstream code grows checks that
must run before anything else can proceed. Nearly always a direct return, an
exception, or a built-in expresses the same thing in one statement.

## Detection heuristics

### Agnostic

- A boolean initialised to `false` (or `true`) purely so a later branch can
  read it, with no meaning outside the enclosing function.
- A counter or accumulator declared above a loop and only meaningful after
  the loop has finished.
- `found`, `ok`, `success`, `valid`, `hasError`, `done`, `flag`, `result` as
  variable names — the name states the mechanism, not the value.
- A loop that could `return` the moment it has the answer but sets a flag and
  keeps going instead.
- The same flag assigned in more than one branch, so establishing its final
  value means tracing every path.
- A flag surviving past the block that computed it — stored on the object,
  returned alongside the real value, or checked again by the caller.
- `while (! $done)` with the exit condition mutated somewhere inside the
  body rather than stated in the condition.

### PHP / Laravel

- `$found = false;` inside a `foreach` where `array_search`, `in_array`,
  `array_any`, or `collect($rows)->contains()` / `->search()` /
  `->first(fn ($row) => …)` answers directly.
- `$success = true;` toggled inside a loop of writes, then checked after,
  instead of wrapping the batch in `DB::transaction()` and letting a failure
  throw.
- `$errors = []` accumulated by hand across a loop where `Validator::make()`
  or a collection `reject()` would collect the same failures.
- Flags promoted to model attributes or `$this` properties — a
  `public bool $processed` on a job or service that exists only to be read by
  the next method, which is a [Temporary Field](temporary-field.md) grown out
  of a local flag.
- `$hasAny = $query->count() > 0;` assigned before a branch, where
  `$query->exists()` reads as the question being asked.
- Blade views computing `$shown = false;` inside `@foreach` to suppress a
  repeat, instead of `@once`, `$loop->first`, or a pre-grouped collection.

### TS / React

- `let found = false` before a `for` loop, where `some`, `find`,
  `findIndex`, or `includes` is a single expression.
- `let result` declared with no initialiser and assigned in branches, instead
  of each branch returning its own value.
- A `useState` boolean that only ever mirrors something derivable —
  `isEmpty`, `hasResults`, `isValid` — recomputed by an effect rather than
  derived inline or with `useMemo`.
- Paired loading flags (`isLoading`, `isError`, `isDone`) hand-maintained
  around a fetch, where a query library's status or a `useReducer` union
  makes the impossible combinations unrepresentable.
- A mutable `let` captured by a callback and read after an `await`, so its
  value depends on scheduling.
- A ref used as a flag (`hasRunRef.current = true`) to make an effect behave
  once, papering over a dependency-array problem.

## Example

Translated from the upstream Python examples.

Smelly — two status variables, a hand-driven index and a `found` flag, and an
infinite loop if `'foo'` is absent:

```php
final class NameIndex
{
    public function findFoo(array $names): int
    {
        $found = false;
        $index = 0;

        while (! $found) {
            if ($names[$index] === 'foo') {
                $found = true;
            } else {
                $index++;
            }
        }

        return $index;
    }
}
```

Solution — the built-in states the question, handles the absent case, and
leaves nothing mutable behind:

```php
final class NameIndex
{
    public function findFoo(array $names): int|false
    {
        return array_search('foo', $names, strict: true);
    }
}
```

The intermediate step is worth knowing even when no built-in fits: keep the
`foreach`, drop both variables, and `return $index;` at the match. Removing
the flag is what makes the missing-element case impossible to get wrong.

## Refactorings

- Replace with Built-In
- Extract Method
- Remove Status Variables

## Related smells

| Smell | Edge |
|---|---|
| [Special Case](special-case.md) | family |
| [Clever Code](clever-code.md) | co-exist |
| [Afraid to Fail](afraid-to-fail.md) | co-exist |
| [Mutable Data](mutable-data.md) | co-exist |
| [Binary Operator in Name](binary-operator-in-name.md) | co-exist |
| [Loops](imperative-loops.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Status Variable" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
