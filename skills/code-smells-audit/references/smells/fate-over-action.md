# Fate over Action

`Between · Couplers · Responsibility`

An object whose data is acted upon entirely from outside itself. In
object-oriented code, data and the behavior over that data are supposed to
travel together; when a type carries only fields, the rules about those
fields have gone somewhere else, usually into a manager, helper, or service
that reaches in, reads state, decides, and writes back. The name comes from
locus of control: the object's outcomes are governed by forces outside it
rather than by its own actions. That inversion violates Tell, Don't Ask and
couples every caller to the object's internal shape, so a field rename ripples
outward and no single place can enforce an invariant. Classes typically start
this way honestly: data is spotted as an independent thing and extracted
before it has grown any behavior, and never finish the journey. Note that a
plain immutable DTO or value type crossing a boundary is not automatically
this smell; the smell is behavior about that data implemented elsewhere.

## Detection heuristics

### Agnostic

- A type is nothing but fields and accessors, while a `*Manager`, `*Helper`,
  or `*Utils` next door holds every rule about them.
- Callers ask for state and then decide, rather than telling the object to
  act; the object's own name never appears as the subject of a verb.
- The same derivation (a total, a validity check, a display label) is
  recomputed from the object's fields at several call sites.
- Setters exist for fields no collaborator has a legitimate reason to change,
  so the object cannot defend its own invariants.
- Behavior that clearly concerns this data lives in a class that had to be
  handed the object to work at all (see [Feature Envy](feature-envy.md)).

### PHP / Laravel

- Eloquent models reduced to `$fillable` and `$casts` while a `*Service`
  reads `$model->attribute`, computes, and assigns back, the rule belongs
  on the model as an accessor, a scope, or a named domain method.
- Decisions made from raw attributes in Blade or Filament
  (`@if ($order->status === 'paid')`) where `$order->isPaid()` would let the
  model own the meaning of "paid".
- DTOs with public mutable properties passed through several layers, each of
  which patches a field on the way; `readonly` promoted properties plus a
  named constructor put the rule back in one place.
- The same validation for one value repeated across FormRequests instead of
  being enforced once by a value object or a custom cast.

### TS / React

- A `type`/`interface` bundle paired with a `utils.ts` of free functions that
  all take that type as their first parameter.
- Components deriving the same value from a prop object inline
  (`item.price * item.tax`) in several places, because the model exposes no
  such property.
- Reducers and selectors reaching into another slice's nested entity fields
  to answer a question that entity's own module could answer.
- State stored as plain mutable objects that any component can patch in
  place, so nothing owns the transition rules.
- Class or factory-built domain objects that expose only getters and setters,
  with every state transition written at the call site.

## Example

Translated from the upstream Python example.

Smelly; the commit is inert data and a separate manager performs every
change on its behalf:

```ts
interface Commit {
  author: string;
  message: string;
}

class CommitManager {
  updateAuthor(commit: Commit, newAuthor: string): void {
    commit.author = newAuthor;
  }

  updateMessage(commit: Commit, newMessage: string): void {
    commit.message = newMessage;
  }
}

const commitManager = new CommitManager();
const commit: Commit = {
  author: 'Marceli Jerzyk',
  message: 'Fix: Button Component styled width w/ rem (from px)',
};
commitManager.updateAuthor(commit, 'Marcel Jerzyk');
```

Solution: the commit owns its own state and the manager disappears:

```ts
class Commit {
  constructor(
    private author: string,
    private message: string,
  ) {}

  setAuthor(newAuthor: string): void {
    this.author = newAuthor;
  }

  setMessage(newMessage: string): void {
    this.message = newMessage;
  }
}

const commit = new Commit(
  'Marceli Jerzyk',
  'Fix: Button Component styled width w/ rem (from px)',
);
commit.setAuthor('Marcel Jerzyk');
```

## Refactorings

- Move Method
- Extract Method
- Freeze Variables

## Related smells

| Smell | Edge |
|---|---|
| [Mutable Data](mutable-data.md) | family |
| [Feature Envy](feature-envy.md) | causes |
| [Data Clump](data-clump.md) | antagonistic |
| [Primitive Obsession](primitive-obsession.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Data Class

---

*Derivative work adapted from "Fate over Action" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
