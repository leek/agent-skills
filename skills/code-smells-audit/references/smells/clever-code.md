# Clever Code

`Within · Obfuscators · Unnecessary Complexity`

Code you can follow, but only by admiring it first. Unlike
[Obscured Intent](obscured-intent.md), its family sibling, the problem here
isn't that the fragment is unreadable — it's that the reader is made to work
out *why* it was written this way, and the answer is usually vanity or
ignorance of the standard library. Two shapes dominate: leaning on a
language's accidental complexity and obscure corners to compress logic into
something surprising, and hand-rolling a mechanism the platform already ships,
often triggered by an [Incomplete Library Class](incomplete-library-class.md)
that was missing one method. Both charge the same tax — every future reader
has to learn a bespoke thing instead of recognising a common one, and the
reimplementation now needs owners, tests, and bug fixes the built-in already
had. The narrow exception is domains where correctness is life-affecting or
legally consequential and the team must be able to vouch for every line, in
which case a deliberate reimplementation is a decision, not a smell.

## Detection heuristics

### Agnostic

- A named helper reimplements something the standard library provides —
  string length, sorting, deduplication, set membership, deep merge, date
  arithmetic.
- An expression whose behavior you have to look up: operator-precedence
  tricks, bit twiddling on non-numeric data, double negation, arithmetic
  identities used as a substitute for the obvious operator.
- The commit that introduced it landed right after the author learned a new
  language feature, and the feature buys nothing here.
- Reviewers ask "what does this do?" rather than "is this correct?".
- A one-liner replacing five clear lines with no measured performance reason,
  and no benchmark in the repo to justify it.
- Custom code that drifts from the built-in it mimics: it handles the happy
  path but not empty input, unicode, or nulls.

### PHP / Laravel

- Hand-written loops doing what an array function already does:
  `array_column`, `array_unique`, `array_fill_keys`, `usort`, `str_contains`,
  `mb_strlen`, `array_is_list`.
- A bespoke collection helper duplicating an existing method — `groupBy`,
  `keyBy`, `partition`, `flatMap`, `sole`, `firstWhere` — instead of
  `Collection::macro()` when a genuinely new operation is needed.
- Reimplemented framework machinery: a custom container, event dispatcher,
  paginator, or "repository" wrapper reproducing what Eloquent, the service
  container, or `LengthAwarePaginator` already do.
- Query cleverness with no plan behind it: raw `DB::select` with nested
  subqueries where a `whereHas` or a join would read plainly, or dynamic
  method names assembled from strings and invoked via `$model->{$method}()`.
- Trait or `__call`/`__get` magic used to create methods that don't appear in
  the source, so neither the reader nor static analysis can find them.
- Blade templates embedding dense inline expressions or nested ternaries
  where a view model or `@php` block would say it once.

### TS / React

- Utility modules re-creating `Array.prototype` behavior — a manual
  `groupBy`, `unique`, `chunk`, or `zip` where `Object.groupBy`, `Set`,
  `flatMap`, or an already-installed library covers it.
- Type-level gymnastics: recursive conditional types or template-literal
  types whose error messages nobody can read, standing in for a plain union
  or a discriminated shape.
- Terse idioms used as control flow — `~arr.indexOf(x)`, `+!!value`,
  `a?.b ?? c ?? d ?? e`, or bit flags on booleans instead of named fields.
- A hand-rolled memoization, debounce, or deep-equality helper alongside a
  dependency that already exports one, or alongside `useMemo` /
  `structuredClone`.
- Custom hooks wrapping `useState` in a novel abstraction (a state machine
  built from `useRef` and closures) where `useReducer` says it directly.

## Example

Translated from the upstream Python examples.

Smelly — a hand-rolled string length, with `-= -1` standing in for `++` for
no reason but sport:

```php
final class MessageStats
{
    public function length(string $message): int
    {
        $length = 0;

        foreach (str_split($message) as $character) {
            $length -= -1;
        }

        return $length;
    }
}
```

Solution — the built-in, which also happens to be the one that handles
multibyte input correctly:

```php
final class MessageStats
{
    public function length(string $message): int
    {
        return mb_strlen($message);
    }
}
```

Smelly — an auto-vivifying array subclass invented so grouping can accumulate
into missing keys:

```php
final class OrdersByStatus extends ArrayObject
{
    public function offsetGet(mixed $key): mixed
    {
        if (! $this->offsetExists($key)) {
            $this->offsetSet($key, []);
        }

        return parent::offsetGet($key);
    }
}

$grouped = new OrdersByStatus();

foreach ($orders as $order) {
    $bucket = $grouped[$order->status];
    $bucket[] = $order;
    $grouped[$order->status] = $bucket;
}
```

Solution — the framework already groups, and every Laravel developer already
knows this line:

```php
$grouped = collect($orders)->groupBy('status');
```

## Refactorings

- Replace with Built-In
- Replace with Library

## Related smells

| Smell | Edge |
|---|---|
| [Obscured Intent](obscured-intent.md) | family |
| [Complicated Regex Expression](complicated-regex-expression.md) | causes |
| [Incomplete Library Class](incomplete-library-class.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Clever Code" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
