# Boolean Blindness

`Within · Lexical Abusers · Names`

A `bool` carries exactly one bit and throws away everything about what that
bit meant. The canonical case is `filter`: given a predicate returning true
or false, does true mean keep the element or discard it? The signature cannot
say, so the reader has to open the implementation or guess — and both
guesses type-check. The smell appears wherever a domain question with a name
(`Keep = Take | Drop`, `Charge = Immediately | OnShipment`) has been
flattened into a raw boolean at a parameter, a return type, or a field. It
is the same family as [Uncommunicative Name](uncommunicative-name.md) and
[Magic Number](magic-number.md): the value is right, the meaning is missing.

## Detection heuristics

### Agnostic

- Call sites that read `f($x, true)` where the literal's meaning is
  unrecoverable without opening the callee.
- A boolean parameter or field named for a mechanism (`$flag`, `$mode`,
  `$opt`) rather than for the domain answer it encodes.
- The same boolean threaded through several layers and inverted somewhere
  along the way (`$excludeDeleted` becoming `$includeDeleted`).
- A comment beside each `true`/`false` argument explaining what it selects —
  the ["What" Comment](what-comment.md) is the cover-up.
- Two or more booleans in one signature or one record where several of the
  combinations are illegal states nobody prevents.

### PHP / Laravel

- Action and service methods taking a `bool`: `$this->refund->handle($order,
  true)` reads as nothing; a backed enum (`RefundMode::Partial`) makes the
  call site self-explanatory.
- Several `boolean` columns cast on one model (`is_active`, `is_archived`,
  `is_draft`) that are really one lifecycle status, plus code enforcing which
  combinations are legal.
- Query scopes parameterized on a boolean (`->visible(true)`) instead of two
  named scopes (`->onlyVisible()` / `->onlyHidden()`).
- Blade component boolean props (`<x-alert :dismissible="true"
  :inline="false" />`) multiplying into variant combinations that a single
  string-backed `variant` enum would cover.
- Methods returning bare `bool` where the caller must distinguish outcomes —
  "not found" versus "found, already up to date" — and cannot.

### TS / React

- Predicate signatures like `filter(items, (i) => boolean)` where the
  polarity lives only in documentation. A returned union (`'take' | 'drop'`)
  moves it into the type.
- Boolean prop sets (`isLoading`, `isError`, `isEmpty`) that a discriminated
  union — `status: 'loading' | 'error' | 'empty' | 'ready'` — would make
  unrepresentable when contradictory.
- Two or more boolean parameters in a row (`format(value, true, false)`);
  TypeScript will not catch a swap because both positions are `boolean`.
- Paired `useState<boolean>` hooks that together encode one state machine and
  can drift out of sync between renders.
- API response types declaring `verified: boolean` where the server actually
  distinguishes pending, verified, and rejected.

## Example

Translated from the upstream Haskell example.

Smelly — the predicate's return type cannot say which way it points:

```ts
declare function filter<T>(items: T[], predicate: (item: T) => boolean): T[];

// Does returning true keep the user, or drop them?
const survivors = filter(users, (user) => user.deletedAt !== null);
```

Solution — give the boolean a type with named inhabitants, and the call site
answers its own question:

```ts
type Keep = 'take' | 'drop';

declare function filter<T>(items: T[], decide: (item: T) => Keep): T[];

const survivors = filter(users, (user) =>
  user.deletedAt === null ? 'take' : 'drop',
);
```

## Refactorings

- Introduce New Type

## Related smells

| Smell | Edge |
|---|---|
| [Uncommunicative Name](uncommunicative-name.md) | family |
| [Magic Number](magic-number.md) | family |
| ["What" Comment](what-comment.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Boolean Blindness" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
