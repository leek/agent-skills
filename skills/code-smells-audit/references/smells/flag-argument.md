# Flag Argument

`Within · Change Preventers · Conditional Logic`

A boolean parameter that selects which of two behaviours the callee performs
puts the decision on the wrong side of the call. `$concert->book($marcel,
false)` tells the reader nothing — *false what?* — so understanding the call
site means opening the method, and the method is really two methods stapled
together behind one name. The literal at the call site is a
[Boolean Blindness](boolean-blindness.md) problem; the branch inside is a
change preventer, because every future variation is cheaper to bolt on as
another flag than to model properly. That is the usual trajectory: the flag
starts as `bool $isPremium`, becomes `string $ticketType`, then a switch over
string codes, and now the method carries
[Conditional Complexity](conditional-complexity.md) with
[Primitive Obsession](primitive-obsession.md) on top. Splitting it into two
named methods — `bookPremium`, `bookRegular` — removes the branch and puts the
meaning back where the reader looks first.

## Detection heuristics

### Agnostic

- A parameter whose only job is to pick a branch, with the whole body wrapped
  in `if ($flag)` / `else`.
- Call sites passing bare literals — `true`, `false`, `0`, `1`, `'full'` —
  that carry no meaning without opening the callee.
- Two or more boolean parameters in one signature, so the reader must decode
  a positional truth table and most combinations are never valid.
- The method's name has to be generic (`process`, `handle`, `save`) because a
  precise name would only describe one of the two behaviours.
- Tests for the method come in matched pairs that share a name and differ only
  in the flag value.
- The flag is threaded through several layers untouched before anything reads
  it, so intermediate functions take a parameter they never use themselves.

### PHP / Laravel

- Action and service methods with trailing switches — `handle(Order $order,
  bool $force, bool $notify)` — where call sites read `handle($order, true,
  false)`.
- Named arguments (`book(customer: $marcel, isPremium: false)`) used to patch
  readability: the call site becomes legible while the two-behaviour method
  stays exactly as it was.
- Boolean-defaulted framework signatures copied into your own code, e.g.
  wrapping `sync($ids, $detaching)` or `withTrashed($withTrashed)` in a
  repository method that forwards the flag instead of exposing two intents.
- Blade components taking boolean props (`<x-button :primary="$isPrimary" />`)
  whose template is one big `@if`/`@else` over two different markup trees.
- Queued jobs whose constructor payload includes a boolean that `handle()`
  branches on, so the queue carries the decision instead of the dispatcher
  choosing the right job class.

### TS / React

- Exported helpers with trailing booleans — `formatDate(date, true)`,
  `fetchUsers(page, includeArchived)` — especially when the flag changes the
  return shape, not just formatting.
- Components taking a mode boolean (`isEditing`, `compact`) and returning two
  substantially different trees from one function body; those are two
  components sharing a props type.
- Sets of mutually exclusive boolean props (`isPrimary`, `isSecondary`,
  `isDanger`) that should be one `variant` union — the type currently permits
  states the component cannot render.
- Callbacks whose signature carries a control flag, e.g.
  `onSelect(id: string, shouldRefetch: boolean)`, pushing caller policy into
  the handler.
- Optional boolean props with defaults, where every consumer passes the
  non-default value and the "default" branch is effectively dead
  ([Dead Code](dead-code.md)).

## Example

Translated from the upstream Python example.

Smelly — the flag chooses the behaviour, and `false` at the call site is
unreadable:

```php
final class Concert
{
    public function book(Customer $customer, bool $isPremium): Booking
    {
        if ($isPremium) {
            return $this->reserve($customer, seating: 'front', lounge: true);
        }

        return $this->reserve($customer, seating: 'general', lounge: false);
    }
}

$concert->book($marcel, false); // false what?
```

Solution — one method per behaviour, so the name carries the meaning the
literal used to hide:

```php
final class Concert
{
    public function bookPremium(Customer $customer): Booking
    {
        return $this->reserve($customer, seating: 'front', lounge: true);
    }

    public function bookRegular(Customer $customer): Booking
    {
        return $this->reserve($customer, seating: 'general', lounge: false);
    }
}

$concert->bookRegular($marcel);
```

When both branches share substantial work, extract the shared part into a
private method first, then split the public surface — the goal is two intents
at the boundary, not two copies of the body.

## Refactorings

- Remove Flag Argument
- Extract Method

## Related smells

| Smell | Edge |
|---|---|
| [Binary Operator in Name](binary-operator-in-name.md) | caused |
| [Long Method](long-method.md) | causes |
| [Long Parameter List](long-parameter-list.md) | causes |
| [Conditional Complexity](conditional-complexity.md) | causes |
| [Loops](imperative-loops.md) | caused |
| [Null Check](null-check.md) | caused |
| [Side Effects](side-effects.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Boolean in Method Parameter

---

*Derivative work adapted from "Flag Argument" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
