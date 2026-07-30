# Lazy Element

`Between · Dispensables · Unnecessary Complexity`

An element — a class, a method, a variable, a module — that does not do
enough to pay for the complexity of existing. Every named thing costs a file
to open, a name to learn, and an indirection to follow; when what you find at
the end is a single field with no invariant, or a method that forwards its
arguments unchanged, the reader paid the cost and got nothing back. Lazy
Elements usually arrive one of two ways: an aggressive refactoring hollowed a
class out and left the shell behind, or a
[Speculative Generality](speculative-generality.md) created a seam for a
future need that never materialised. Judgement matters here, because the
opposite mistake is [Primitive Obsession](primitive-obsession.md) — a wrapper
that enforces a rule, carries a unit, or makes an illegal state
unrepresentable is earning its keep, and only the one that does none of those
is lazy.

## Detection heuristics

### Agnostic

- A class holding one field with no validation, no invariant, and no
  behaviour beyond getting and setting it.
- A method whose body is a single call to another method with the same
  arguments, under a name that adds no meaning.
- Every use site immediately unwraps the element — the wrapper exists only to
  be taken apart.
- A subclass that adds no fields, no overrides, and no behaviour; only a
  name.
- An interface with exactly one implementer, no test double, and no plugin
  point.
- A module whose entire content is a re-export of another module.
- A class that git history shows used to be substantial, with methods moved
  out one by one and never the last one.

### PHP / Laravel

- Value objects wrapping one scalar with no validation, formatting, or
  comparison logic, where callers reach straight through to `->value`.
- Repository or `*Service` classes whose methods forward one-to-one to
  Eloquent (`findById($id)` returning `User::find($id)`), adding no query
  vocabulary of their own.
- An interface bound to its single implementation in `AppServiceProvider`
  with nothing ever swapping it — not in tests, not per environment.
- Abstract base controllers, models, or jobs with no shared code left in
  them after the shared parts were pulled elsewhere.
- Traits holding one short method used by one class.
- Query scopes that rename a single condition without naming a domain rule —
  `scopeWhereUserId()` rather than `scopeVisibleTo()`.
- FormRequests whose `rules()` returns another class's rules verbatim.
- Blade components that render one HTML element and pass every attribute
  straight through.

### TS / React

- Components that render exactly one child with the same props
  (`<Wrapper {...props} />`) and no styling, defaults, or conditional logic.
- Custom hooks that call one library hook and return its result unchanged.
- Barrel `index.ts` files re-exporting a single module.
- Single-property interfaces (`{ value: number }`) that callers destructure
  at every use site.
- Context providers holding one constant that never changes — a module
  export would say the same thing.
- Modules exporting one one-line helper used from one place.
- Type aliases layered over other aliases without narrowing, branding, or
  documenting anything new.

## Example

Translated from the upstream Python example.

Smelly — `Strength` wraps a number and adds nothing, and `strengthValue()`
exists only to unwrap it again:

```ts
class Strength {
  constructor(readonly value: number) {}
}

class Person {
  constructor(
    readonly health: number,
    readonly intelligence: number,
    readonly strength: Strength,
  ) {}

  strengthValue(): number {
    return this.strength.value;
  }
}
```

Solution — inline the wrapper; the field is a number and always was:

```ts
class Person {
  constructor(
    readonly health: number,
    readonly intelligence: number,
    readonly strength: number,
  ) {}
}
```

Had `Strength` clamped its value to 1–20, refused negatives, or made a
strength score impossible to pass where an intelligence score was expected,
it would have earned its place — the test is what the type guarantees, not
whether it exists.

## Refactorings

- Inline Class
- Inline Method
- Collapse Hierarchy

## Related smells

| Smell | Edge |
|---|---|
| [Dubious Abstraction](dubious-abstraction.md) | family |
| [Speculative Generality](speculative-generality.md) | caused |
| [Primitive Obsession](primitive-obsession.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Lazy Class

---

*Derivative work adapted from "Lazy Element" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
