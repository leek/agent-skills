# Insider Trading

`Between · Data Dealers · Responsibility`

Two classes — or, in the modern framing, two modules — that know each other's
internals so well neither can be understood or changed alone. Fowler's
original name, *Inappropriate Intimacy*, carried the image: each one reaches
past the other's public surface into data and implementation details it was
never meant to see. The 2018 rename generalized classes to modules, but the
failure is unchanged — knowledge that should have stayed behind one boundary
is traded across two. It rarely starts that way. Two collaborators that
legitimately talk to each other accumulate one convenience accessor at a
time, until the association runs in both directions and the pair is really a
single unit with a seam drawn through the middle of it. What you pay for is
coupling you cannot localize, two classes that can no longer be reused apart,
and tests that must stand up the other half before they can assert anything.

## Detection heuristics

### Agnostic

- Each class holds a reference to the other and calls back into it, so a
  change to either means reading both.
- Accessors that exist for exactly one caller — a getter or setter added to
  expose a field to one specific collaborator and used nowhere else.
- A method body that is mostly `other->x`, `other->y`, deciding on another
  object's data rather than its own (see [Feature Envy](feature-envy.md)).
- A subclass reaching into its parent's protected internals, or a parent
  branching on which subclass it happens to be holding.
- Renaming or reshaping a private field breaks code in a different file.

### PHP / Laravel

- Two Eloquent models that each define relations back onto the other *and*
  each compute their own state by walking the other's rows — `Order`
  totalling `$this->invoice->lines` while `Invoice` re-derives status from
  `$this->order`. The relation pair is fine; the two-way derivation is not.
- Code outside a model reading its internals through `getAttributes()`,
  `getRawOriginal()`, or `getDirty()` to reconstruct a decision the model
  should have made.
- Mutators or scopes added to a model solely because one listener, job, or
  Filament resource needs to poke a specific column.
- A trait used to share mutable state between two collaborating classes
  rather than to share behaviour, so each class's fields are effectively
  public to the other.
- Tests that need a partial `Mockery` mock of the second class before the
  first can be exercised at all.

### TS / React

- Modules importing from each other's internal paths (`../auth/internal/store`)
  instead of a package entry point — often visible as a circular import.
- A child component handed a parent's raw `setState` and expected to know
  which shape the parent keeps its state in.
- A custom hook that returns internal refs or unnormalized state only one
  component knows how to interpret, so hook and component ship as a pair.
- Context consumers destructuring the provider's internal state shape rather
  than calling a stable API the provider exposes.
- A test that must render two components together because neither renders
  meaningfully on its own.

## Example

Translated from the upstream Python example.

Smelly — the association runs both ways, and each class calls a method on the
other that exists only for it:

```php
final class Commit
{
    public function __construct(public string $name)
    {
    }

    public function push(Repo $repo): void
    {
        $repo->push($this->name);
    }

    public function commit(string $url): void
    {
        // ...
    }
}

final class Repo
{
    public function __construct(public string $url)
    {
    }

    public function push(string $name): void
    {
        // ...
    }

    public function commit(Commit $commit): void
    {
        $commit->commit($this->url);
    }
}
```

Solution — the behaviour moves to the class that owns the data it needs, and
the association points one way:

```php
final class Commit
{
    public function __construct(public string $name)
    {
    }
}

final class Repo
{
    public function __construct(public string $url)
    {
    }

    public function push(Commit $commit): void
    {
        // ...
    }

    public function commit(Commit $commit): void
    {
        // ...
    }
}
```

## Refactorings

- Move Method
- Move Field
- Encapsulate Field
- Replace Inheritance with Delegation
- Change Bidirectional Association to Unidirectional

## Related smells

| Smell | Edge |
|---|---|
| [Fate over Action](fate-over-action.md) | caused |
| [Feature Envy](feature-envy.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Inappropriate Intimacy

---

*Derivative work adapted from "Insider Trading" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
