# Refused Bequest

`Between · Object Oriented Abusers · Interfaces`

A subclass inherits the whole of its parent, data, methods, and the promise
that it can stand in for the parent anywhere, and then declines part of the
inheritance. The refusal can be explicit, an override that throws "not
supported", or implicit, an inherited routine that simply does not work for
this child, or fields that are never populated. Fowler is relaxed about the
mild version: reusing only some of a parent's behaviour is common and rarely
fatal. The strong version, which he and Mäntylä both single out, is the
subclass that happily reuses the *implementation* while refusing the
*interface*; it wanted the code, not the type. That is a Liskov violation, and
it shows up in callers that must check which concrete class they hold before
deciding which inherited method is safe to call. The cause is almost always
opportunistic: the behaviour needed already existed on some class, `extends`
was the fastest way to reach it, and the resulting "is-a" claim was never true.
When the hierarchy is a convenient lie, the fix is composition: hold the old
parent as a collaborator instead of inheriting it, which is where
[Dubious Abstraction](dubious-abstraction.md) and this smell tend to be found
together.

## Detection heuristics

### Agnostic

- An override whose whole body throws, "not supported", "not implemented",
  "unreachable", or returns `null` / does nothing, on a member the parent
  declares as meaningful.
- A subclass that uses a small fraction of what it inherits; most inherited
  fields stay unset, default, or null for that child.
- Callers type-check before invoking an inherited method, so the polymorphism
  the hierarchy advertises never actually gets used.
- A doc comment or test warning that a method "must not be called on X".
- The inheritance was introduced by a commit that needed exactly one helper
  method from the parent.
- The subclass's tests assert that a method throws; the contract is documented
  as broken.
- An override narrows what the parent accepts (stricter validation, fewer
  argument types) or widens what it may throw.

### PHP / Laravel

- `throw new BadMethodCallException()` or `LogicException` inside an override,
  or an override reduced to an empty body with a "no-op for this type"
  comment.
- Single-table-inheritance Eloquent children that inherit relations, scopes,
  and casts belonging to their siblings, so half the accessors return null for
  any given row.
- One model extending another to borrow its casts, scopes, or helpers, the
  tell is the child redeclaring `$table`, which means it is a different thing
  wearing its parent's methods.
- A base `Job`, `Command`, or `Service` whose template method calls hooks that
  several children stub out empty, so the "shared" algorithm is shared by
  nobody in full.
- `extends` where a trait or an injected collaborator was meant: the child
  wanted the behaviour, never the type. Traits and constructor injection give
  you the code without the substitutability claim.
- A fat interface implemented across drivers where each driver throws for the
  parts it cannot do; a read-only storage adapter throwing on writes. Split
  the contract instead.
- PHPStan or Psalm complaining about a narrowed parameter type or a widened
  return in an override is the mechanical version of this smell.

### TS / React

- Overrides that `throw new Error('not supported')`, or interface members
  implemented as `undefined`, `never`, or an empty body.
- A base props type where most fields are optional because each subclass or
  variant only uses a few; the optionality is the refusal.
- Call sites doing `if (unit instanceof Tower) return;` before invoking an
  inherited method.
- A class component extended from a base component purely to reuse one method, 
  a hook or a plain function gives the same reuse without the hierarchy.
- Discriminated unions whose shared branch carries fields only some members
  ever set; splitting the union removes the refusal.

## Example

Translated from the upstream Python example, which shows only the smelly
half; the solution is authored for this card.

Smelly: `Tower` wants the attacking behaviour but cannot honour `move`:

```ts
abstract class Minion {
  abstract attack(target: Unit): void;
  abstract move(to: Point): void;
}

class Footman extends Minion {
  attack(target: Unit): void { /* swing at target */ }
  move(to: Point): void { /* walk toward to */ }
}

class Tower extends Minion {
  attack(target: Unit): void { /* fire at target */ }

  move(_to: Point): void {
    throw new Error('Towers cannot move');
  }
}
```

Solution; the bequest is split so nothing has to be refused, and the shared
behaviour arrives by delegation rather than by inheritance:

```ts
interface Attacker {
  attack(target: Unit): void;
}

interface Mobile {
  move(to: Point): void;
}

class Tower implements Attacker {
  private readonly targeting = new NearestTargeting();

  attack(target: Unit): void { /* fire at this.targeting.acquire(target) */ }
}

class Footman implements Attacker, Mobile {
  private readonly targeting = new NearestTargeting();

  attack(target: Unit): void { /* swing at this.targeting.acquire(target) */ }
  move(to: Point): void { /* walk toward to */ }
}

function advance(units: Mobile[], to: Point): void {
  units.forEach((unit) => unit.move(to));
}
```

`advance` can no longer be handed a tower, and the compiler enforces it. When
the child genuinely needs the parent's implementation but not its type, that is
the strong form of the smell and Replace Superclass with Delegate is the direct
fix; when it is only a few unused inherited fields, pushing them down to the
siblings that use them is enough.

## Refactorings

- Extract Subclass
- Push Down Field
- Push Down Method
- Replace Inheritance with Delegation
- Replace Superclass with Delegate
- Replace Subclass with Delegate

## Related smells

| Smell | Edge |
|---|---|
| [Dubious Abstraction](dubious-abstraction.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Refused Parent Bequest

---

*Derivative work adapted from "Refused Bequest" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
