# Combinatorial Explosion

`Within · Bloaters · Responsibility`

A pile of code that all does almost the same thing, where "almost" is the
whole problem. Independent choices, which transport, which format, which
filter, which state: were folded into a single hierarchy or a single chain
of branches instead of being kept as separate decisions, so the number of
methods and cases is the product of the options rather than their sum. Adding
one option along any axis multiplies the work: a variant has to be written
for every existing combination, and nobody can recall which of the
near-identical versions handles which edge case. Wake describes it as a
relative of Parallel Inheritance Hierarchies with everything folded into one
hierarchy. It breaks DRY, because the shared behavior is restated once per
combination, and Open–Closed, because the shape of the code invites another
`elseif` rather than a new collaborator.

## Detection heuristics

### Agnostic

- Method names read as a matrix; the option grid is spelled out in the
  identifiers rather than expressed as parameters or collaborators.
- Adding one option along one axis means writing N new methods or cases, not
  one.
- Several conditionals in the same class branch on the same field in the same
  order (see [Conditional Complexity](conditional-complexity.md)).
- The variants differ only in constant data, a string, a format, a count, 
  never in structure.
- Subclasses are named after combinations of traits rather than after
  concepts, folding two hierarchies into one (see
  [Parallel Inheritance Hierarchies](parallel-inheritance-hierarchies.md)).

### PHP / Laravel

- A repository or service exposing `activeUsersByTeam()`,
  `activeUsersByTeamPaginated()`, `archivedUsersByTeam()` … where composable
  Eloquent scopes or a query object cover the same axes.
- Notification and mailable classes duplicated per event × per channel
  (`OrderShippedMail`, `OrderShippedSms`, `RefundIssuedMail`, …) instead of
  one notification whose `via()` returns the channels.
- Model methods that `match` or `switch` on the same `status` string in
  several places, where a backed enum implementing a state interface collapses
  them into one dispatch.
- Blade partials or Filament resources duplicated per role × per record type,
  rather than one component driven by policy checks.
- Repeated `if ($driver === 's3') … elseif ($driver === 'local')` chains,
  when the filesystem manager already resolves the implementation by name.

### TS / React

- Component families named by combination, `PrimaryLargeButton`,
  `PrimarySmallButton`, `GhostLargeButton`: where the axes are props and a
  variant lookup.
- One hook per data shape × per fetch mode (`useUserList`,
  `useUserListPolling`, `useTeamList`, `useTeamListPolling`) where a single
  parameterized hook covers all four.
- Reducer action types multiplying as `SET_X_LOADING`, `SET_X_ERROR`,
  `SET_Y_LOADING`, `SET_Y_ERROR` … instead of a status field per resource.
- Nested ternaries in JSX over the same pair of enums, repeated across sibling
  components.
- The same `switch` over a discriminated union written out in several modules,
  when the behavior belongs on the union members or in one lookup record.

## Example

Translated from the upstream Python example.

Smelly; every method re-derives the same state grid, so a fourth state means
editing all of them:

```ts
type StateName = 'ready' | 'fighting' | 'resting';

class Minion {
  name = '';
  state: StateName = 'ready';

  action(): void {
    if (this.state === 'ready') this.animate('standing');
    else if (this.state === 'fighting') this.animate('fighting');
    else if (this.state === 'resting') this.animate('resting');
  }

  nextState(): StateName {
    if (this.state === 'ready') return 'fighting';
    if (this.state === 'fighting') return 'resting';
    return 'ready';
  }

  animate(animation: string): void {
    console.log(`${this.name} is ${animation}!`);
  }
}
```

Solution: each state owns its own answers and the minion delegates, so a new
state is one entry rather than one branch per method:

```ts
type StateName = 'ready' | 'fighting' | 'resting';

interface State {
  next(): StateName;
  animate(): string;
}

const states: Record<StateName, State> = {
  ready: { next: () => 'fighting', animate: () => 'standing' },
  fighting: { next: () => 'resting', animate: () => 'fighting' },
  resting: { next: () => 'ready', animate: () => 'resting' },
};

class Minion {
  constructor(
    readonly name: string,
    private state: StateName = 'ready',
  ) {}

  action(): void {
    console.log(`${this.name} is ${states[this.state].animate()}!`);
  }

  nextState(): void {
    this.state = states[this.state].next();
  }
}
```

## Refactorings

- Replace Inheritance with Delegation
- Tease Apart Inheritance

## Related smells

| Smell | Edge |
|---|---|
| [Conditional Complexity](conditional-complexity.md) | family |
| [Parallel Inheritance Hierarchies](parallel-inheritance-hierarchies.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Combinatorial Explosion" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
