# Tramp Data

`Between · Data Dealers · Data`

A value hitchhikes through a run of methods that have no use for it. Each one
declares the parameter, forwards it untouched, and only the last frame in the
line actually reads it. Where [Message Chain](message-chain.md) is the caller
walking to distant data, this is the data being walked to the caller — same
coupling, opposite direction. The tell is that the parameter does not belong
to the abstraction each intermediate signature claims to present, which is
what makes it a form of [Dubious Abstraction](dubious-abstraction.md): a
method that says it renders a row should not need a session token to do it.
It often appears as the cheap escape from [Global Data](global-data.md) —
the global was removed, but the value it carried was threaded through every
signature instead of being moved next to the behaviour that uses it, which is
what the Law of Demeter asks for.

## Detection heuristics

### Agnostic

- A parameter is present in three or more stacked frames and read only in the
  last one.
- Intermediate methods name the parameter but reference it nowhere except the
  forwarding call.
- Adding one field to a payload means editing every signature between the
  producer and the single consumer.
- The parameter's type sits at a different level of abstraction than the
  method that accepts it — a transport or request type deep inside domain
  code.
- Removing the parameter from a middle layer is a purely mechanical edit with
  no logic to reason about.
- Generic `context` or `options` bags forwarded downward, used as a channel
  for values that never belonged to the intermediate layers.

### PHP / Laravel

- The `Request` object (or `$request->user()`) passed controller → service →
  repository so a query builder can read one input; the layers below want the
  scalar, or a DTO built at the edge.
- Whole Eloquent models handed to a nested Action purely so the innermost one
  can read `$model->id`, when the intermediate steps never touch the model.
- Blade `@include('rows', ['order' => $order, 'currency' => $currency])`
  chains where `$currency` is only read two partials down — component slots
  or a view model end the relay.
- Auth context threaded by hand through service calls where a Gate check, a
  policy, or an injected `AuthManager` would let each layer ask for what it
  needs.
- Event payloads carrying fields only one listener reads, forcing every
  `dispatch()` site to compute them.

### TS / React

- Prop drilling: a value passed through three or more components that only
  hand it further down. Context, a store, or passing `children` through the
  middle removes the relay.
- Handlers re-wrapped to forward arguments they ignore —
  `onChange={(event, meta) => onChange(event, meta)}` where `meta` is read
  only at the leaf.
- Custom hooks that accept a config object solely to spread it into another
  hook.
- Next.js page props forwarded whole through a server component tree so one
  client leaf can read a single field, which also inflates the serialized
  payload.
- Test renderers that require a long list of unrelated props just to satisfy
  the intermediate components' signatures.

## Example

Translated from the upstream Python example, which shows only the smelly
half; the solution is authored for this card.

Smelly — the turn timer is declared at every level of the walk and read only
by `Troop`:

```php
final class Game
{
    private Round $round;
    private int $timer;

    public function startTurn(): void
    {
        $this->round->advance($this->timer);
    }
}

final class Round
{
    private Field $field;

    public function advance(int $timer): void
    {
        $this->field->advance($timer);   // never reads $timer
    }
}

final class Field
{
    /** @var list<Troop> */
    private array $troops;

    public function advance(int $timer): void
    {
        foreach ($this->troops as $troop) {
            $troop->advance($timer);     // never reads $timer either
        }
    }
}

final class Troop
{
    public function advance(int $timer): void
    {
        // the only place the timer is actually used
    }
}
```

Solution — give the timer to the object that reads it and the intermediate
signatures lose a parameter they were only babysitting:

```php
final class Game
{
    private Round $round;

    public function startTurn(): void
    {
        $this->round->advance();
    }
}

final class Round
{
    private Field $field;

    public function advance(): void
    {
        $this->field->advance();
    }
}

final class Field
{
    /** @var list<Troop> */
    private array $troops;

    public function advance(): void
    {
        foreach ($this->troops as $troop) {
            $troop->advance();
        }
    }
}

final class Troop
{
    public function __construct(private TurnClock $clock)
    {
    }

    public function advance(): void
    {
        $elapsed = $this->clock->elapsed();
        // ...
    }
}
```

Some data has to cross module boundaries; the goal is balance rather than
zero. Push too hard here and the shared collaborator becomes
[Global Data](global-data.md), or the walk itself becomes a
[Message Chain](message-chain.md).

## Refactorings

- Extract Method
- Hide Delegate
- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Message Chain](message-chain.md) | family |
| [Long Parameter List](long-parameter-list.md) | co-exist |
| [Dubious Abstraction](dubious-abstraction.md) | co-exist |
| [Global Data](global-data.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Tramp Data" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
