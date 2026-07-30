# Conditional Complexity

`Within · Object Oriented Abusers · Conditional Logic`

An `if`/`elseif` cascade or `switch` that dispatches on a type code, and grows
a branch every time the product grows a feature. The first branch is fine; the
second is the warning. What makes it a smell is not the `switch` keyword —
Mäntylä's correction to Fowler's original *Switch Statement* naming, which
Fowler later accepted by renaming it *Repeated Switching* — but the fact that
the same set of cases reappears elsewhere in the codebase. Once it does,
adding a variant means finding and editing every copy, which is an Open-Closed
violation and the mechanism behind [Shotgun Surgery](shotgun-surgery.md).
Each branch also carries its own behaviour and its own dependencies, so the
class ends up with as many reasons to change as it has cases, and the test
suite grows one path per branch. The alternative is to let the object answer:
a class per variant behind a shared interface, resolved from a map, so adding
a case adds a file instead of editing four. The same shape appears in nested
`try`/`catch` checklists, where a stack of handlers per exception type does
near-identical work; and stacking these cascades inside one another produces
[Combinatorial Explosion](combinatorial-explosion.md) or, in asynchronous
code, [Callback Hell](callback-hell.md).

## Detection heuristics

### Agnostic

- The same set of cases is switched on in more than one place — a new variant
  means editing all of them, and forgetting one is silent.
- The branch condition reads a type code, status string, or enum
  discriminator, rather than asking the object to act.
- Each branch is a whole behaviour with its own collaborators, not a small
  variation on a shared expression.
- Git history shows the block gaining exactly one branch per feature, never
  losing any.
- A default or fall-through case that either does nothing or throws, because
  nobody knows whether the list is complete.
- Test count scales with branch count, and the tests construct discriminator
  values rather than meaningful scenarios.

### PHP / Laravel

- A `match ($type)` or `switch ($status)` in a service that maps each case to
  its own method, mirrored by a `@switch`/`@case` block in Blade and a third
  copy in a notification.
- Branching on a string column — `if ($user->role === 'admin') { ... }
  elseif ($user->role === 'editor')` — where a backed enum implementing a
  behaviour interface, or a policy, would carry the decision.
- Controllers dispatching on `$request->input('type')` instead of resolving
  an implementation from a container binding, a tagged set
  (`app()->tag(...)`), or an enum-keyed map.
- Hand-rolled driver selection by conditional where Laravel's manager pattern
  already exists: extend `Illuminate\Support\Manager` with
  `createXDriver()` methods and `extend()`, as `Storage` and `Cache` do.
- Notifications deciding delivery with cascading ifs inside `toMail()` rather
  than returning the applicable channels from `via()`.

### TS / React

- A `switch (action.type)` reducer where each case holds domain logic rather
  than a state transition — the dispatch table is fine, the business rules
  inside it are not.
- Components selecting output by string prop
  (`if (variant === 'primary') return <Primary />; ...`) where a
  `Record<Variant, ComponentType>` map would do it in one line.
- A discriminated union switched on in several modules; add the
  `assertNever(x: never)` exhaustiveness helper and the compiler will list
  every duplicate site for you.
- Chained ternaries in JSX choosing between four or more renderings, usually
  with the deepest arm holding the error state.
- Cascading `if`/`else` over independent flags (`isLoading`, `isError`,
  `isSuccess`) where the states are actually one union and the combinations
  are mostly illegal.

## Example

Translated from the upstream Python example.

Smelly — a branch per format, and every new codec edits this method:

```php
final class Exporter
{
    public function export(string $format): void
    {
        if ($format === 'wav') {
            $this->exportInWav();
        } elseif ($format === 'flac') {
            $this->exportInFlac();
        } elseif ($format === 'mp3') {
            $this->exportInMp3();
        } elseif ($format === 'ogg') {
            $this->exportInOgg();
        }
    }
}
```

Solution — each format is a class behind one interface, and `Exporter` looks
the implementation up instead of knowing the list:

```php
interface FormatExporter
{
    public function export(Track $track): void;
}

final class Exporter
{
    /** @param array<string, FormatExporter> $formats */
    public function __construct(
        private readonly array $formats,
    ) {}

    public function export(Track $track, string $format): void
    {
        $exporter = $this->formats[$format]
            ?? throw new MissingFormatException($format);

        $exporter->export($track);
    }
}
```

Note what survives: one lookup that can still fail. The goal was never to
delete every conditional, only to stop repeating this one — adding FLAC now
means adding a class and a map entry in a service provider, with `Exporter`
untouched.

## Refactorings

- Use Guard Clauses
- Extract Conditional
- Replace Conditional with Polymorphism
- Use Strategy Pattern
- Introduce Null Object
- Use Functional Programming Based Solution

## Related smells

| Smell | Edge |
|---|---|
| [Callback Hell](callback-hell.md) | family |
| [Combinatorial Explosion](combinatorial-explosion.md) | family |
| [Flag Arguments](flag-argument.md) | caused |
| [Loops](imperative-loops.md) | caused |
| [Null Check](null-check.md) | caused |
| [Long Parameter List](long-parameter-list.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Repeated Switching, Switch Statement, Conditional Complexity, Prefer
Polymorphism to if/else or switch/case

---

*Derivative work adapted from "Conditional Complexity" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
