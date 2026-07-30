# Complicated Boolean Expression

`Within · Obfuscators · Conditional Logic`

A condition that has to be *evaluated* rather than *read*. Stack up a few
negations, mix `&&` with `||`, lean on operator precedence, and the reader
stops asking "what rule is this?" and starts doing discrete maths at the
keyboard — even though the rule underneath is often something as plain as
"the timer is finished with". Wake's remedies are De Morgan's laws, to
collapse negations, and guard clauses, to peel layers off the front of the
expression. Robert Martin's is blunter and arguably more valuable: give the
expression a name, because a well-named predicate is understood at a glance
and a boolean expression never is — even a two-term one. Double negatives are
the worst offenders (`if (! $task->isNotDone())`), since the name and the
operator each carry a negation, which is how this smell breeds
[Obscured Intent](obscured-intent.md) and the explanatory
["What" Comments](what-comment.md) that get pasted above the `if` in
apology. A boolean parameter threaded into the condition
(see [Flag Argument](flag-argument.md)) quietly adds a term the reader cannot
see from the call site.

## Detection heuristics

### Agnostic

- Three or more logical operators in one condition, or any mix of `&&` and
  `||` that needs parentheses to disambiguate.
- A negation applied to an already-negative name: `!isInvalid()`,
  `!hasNoAccess()`.
- A comment directly above the `if` restating the condition in English — the
  comment is the method name the condition is missing.
- The condition wraps across lines, and answering "when is this true?"
  requires reading it twice.
- The truth table has eight or more rows, and the tests enumerate operand
  combinations instead of named business cases.
- Boolean parameters or config flags appear as operands, so whether the branch
  fires depends on caller context invisible at the condition.

### PHP / Laravel

- Blade conditions carrying business rules:
  `@if ($user->subscribed() && ! $user->onTrial() && ! $order->isRefunded())`
  — a policy-shaped decision with no name, evaluated in a view.
- Gate and policy methods that `return` one compound expression instead of
  composing named private predicates:
  `Gate::define('update-post', fn ($user, $post) => ...)` with stacked `&&`.
- `when()` / `unless()` on the query builder handed a compound expression as
  the first argument, so the reason the clause applies is unrecoverable.
- Nested `where(function (Builder $query) { ... })` groups mixing `orWhere`
  and `whereNot` — the same smell expressed in SQL, and just as unreadable.
- `match (true)` arms whose conditions each contain multiple clauses, or
  `Rule::when($a && ! $b, [...])` deciding validation from an unnamed
  expression.

### TS / React

- Conditional rendering as a truth table:
  `{user && !user.isGuest && (flags.beta || isAdmin) && <Panel />}`.
- Boolean props computed at the call site —
  `disabled={!isValid || isSubmitting || (isDirty && !autosave)}` — so the
  rule lives in JSX rather than in a named hook or selector.
- `useMemo` / `useEffect` bodies that open with a compound early return, while
  the dependency array gives no hint which operand actually drives it.
- State narrowed by combinations of independent booleans
  (`if (loading && !error && data)`) where a discriminated union on a `status`
  field would make the illegal combinations unrepresentable.
- `&&` chains in JSX mixing truthiness with real booleans, which is both hard
  to read and how a literal `0` ends up rendered.

## Example

Translated from the upstream Python example.

Smelly (Robert C. Martin) — two terms and a negation, and the rule still has
no name:

```php
if ($timer->hasExpired() && ! $timer->isRecurrent()) {
    // ...
}
```

Solution (Robert C. Martin) — the same logic, stated:

```php
if ($this->shouldBeDeleted($timer)) {
    // ...
}
```

Smelly — a flag parameter, a nested `if`, and a conjunction with a negated
half:

```php
final class Kitchen
{
    public function cook(bool $ready, array $bag): void
    {
        if ($ready) {
            if ($this->containsAll($bag, ['raspberry', 'apple', 'tomato'])
                && ! $this->containsAll($bag, ['carrot', 'spinach', 'garlic'])) {
                // ...
            }
        }
    }
}
```

Solution — the flag is lifted out to the caller, the operands get names, and
guard clauses peel the conjunction apart:

```php
final class Kitchen
{
    public function cook(array $bag): void
    {
        if (! $this->hasFruit($bag)) {
            return;
        }

        if ($this->hasVegetables($bag)) {
            return;
        }

        // ...
    }

    private function hasFruit(array $bag): bool
    {
        return $this->containsAll($bag, ['raspberry', 'apple', 'tomato']);
    }

    private function hasVegetables(array $bag): bool
    {
        return $this->containsAll($bag, ['carrot', 'spinach', 'garlic']);
    }

    private function containsAll(array $bag, array $items): bool
    {
        return array_diff($items, $bag) === [];
    }
}
```

## Refactorings

- Extract Method
- Extract Variable
- Use Guard Clauses
- Simplify Conditional

## Related smells

| Smell | Edge |
|---|---|
| [Complicated Regex Expression](complicated-regex-expression.md) | family |
| [Obscured Intent](obscured-intent.md) | causes |
| [Flag Argument](flag-argument.md) | caused |
| ["What" Comments](what-comment.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Complicated Boolean Expression" in Marcel
Jerzyk's [Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
