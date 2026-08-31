# Fallacious Method Name

`Within · Lexical Abusers · Names`

A method whose name promises one contract while its body honors another.
Decades of practice have welded certain words to certain behavior: `get`
returns without side effects, `is` and `has` answer yes or no, `set` stores
and returns nothing, a plural name yields a collection, a validator refuses
invalid input. When a name breaks one of those ties, every caller has to open
the body to learn what it really does, and any caller who trusts the name
instead ships a bug. Detect it by reading the name as a promise and checking
the signature and body against it, the return type, the cardinality, and
whether anything is mutated or fetched along the way.

## Detection heuristics

### Agnostic

- A plural or collection name returning a single instance, or a singular name
  returning a collection.
- An `is` / `has` / `can` prefix on a method whose return type is not boolean,
  or that returns a third state such as null.
- A `get` that mutates state, performs I/O, or lazily creates something, 
  more than an accessor, at a call site that reads as free.
- A `set` that returns a value, mixing a command with a query so callers
  cannot tell which they are invoking.
- A `validate` or `check` that returns a verdict nobody is forced to inspect
  instead of refusing the invalid input.

### PHP / Laravel

- Eloquent relations named against their cardinality: a `hasMany` called
  `role()` hands back a Collection, a `belongsTo` called `comments()` hands
  back one model, and every `$user->role` in the codebase misleads.
- Accessors (`Attribute::get()` or `getFooAttribute()`) that write, dispatch a
  job, or hit an API: property reads should not have side effects.
- `is*` / `has*` methods declared `: ?bool`, `: string`, or `: int`; the
  native return type is the check the name failed.
- Query scopes that execute the query (`->get()`, `->first()`) instead of
  returning the Builder, breaking the chain every `scope*` name implies.
- A `get*` on a service that is really a find-or-create, it persists a row
  the caller never asked it to write.

### TS / React

- A `use*`-prefixed function that is not a hook, or a hook called
  conditionally; the prefix is a contract that
  `eslint-plugin-react-hooks` enforces on everything wearing it.
- Boolean-named props or state (`isLoading`, `hasError`) typed as a string
  union or `boolean | undefined`: the name promises two states, the type
  carries three.
- `handleX` / `onX` callbacks doing work beyond the event they name:
  navigating, firing analytics, mutating unrelated state.
- Selectors or reducers named `get*` that dispatch or mutate, React assumes
  they are pure and may call them more than once per render.
- A function named as if it completes the work but returning before its
  request settles, so `await`-less callers report success that never happened.

## Example

Translated from the upstream Python example.

Smelly: three signatures, three broken promises: a plural name yielding one
item, an `is` returning prose, and a setter that also answers:

```ts
class FooStore {
  private value = 0;

  getFoos(): Foo {
    return this.load()[0];
  }

  isGoo(): string {
    return 'yes';
  }

  setValue(value: number): number {
    this.value = value;
    return this.value;
  }
}
```

Solution; each signature is brought back in line with what its name already
told the caller to expect:

```ts
class FooStore {
  private value = 0;

  getFoos(): Foo[] {
    return this.load();
  }

  isGoo(): boolean {
    return true;
  }

  setValue(value: number): void {
    this.value = value;
  }
}
```

## Refactorings

- Rename Method

## Related smells

| Smell | Edge |
|---|---|
| [Fallacious Comment](fallacious-comment.md) | family |
| [Obscured Intent](obscured-intent.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

"Set" Method returns, "Get" Method does not Return, "Get" Method - More than
an Accessor, "Is" Method - More than a Boolean, Expecting but not getting a
collection, Expecting but not getting a single instance, Not answered
question, Validation method does not confirm, Use Standard Nomenclature Where
Possible

---

*Derivative work adapted from "Fallacious Method Name" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
