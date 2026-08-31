# Vertical Separation

`Within · Obfuscators · Measured Smells`

Declarations placed far from where they are used: variables batched at the
top of a method before the logic begins, helpers stranded pages away from
their only caller, members grouped by visibility instead of by feature. The
distance forces the reader to hold context across the gap, by the time the
variable finally matters, they've forgotten what it was for. Region markers
and folding banners are the same smell with tooling support: they organize
the distance instead of removing it, and are often a cheap deodorant for a
method or class that is simply too large. The habit sometimes survives from
old declare-everything-first optimization styles that compilers made
pointless long ago.

## Detection heuristics

### Agnostic

- A variable declared many lines before its first use.
- A helper function or method far from its single caller, related things
  should sit next to each other, ideally the helper directly below first use.
- Class members grouped by visibility or kind (all constants, all fields,
  all public, all private) with no regard for which feature each belongs to.
- `#region`-style markers or banner comments (`// ---- helpers ----`) doing
  the organizing that extraction should do.
- The file is only navigable with everything folded.

### PHP / Laravel

- Long controller or service methods opening with a block of local
  assignments consumed only much later, usually a
  [Long Method](long-method.md) wearing its phases on its sleeve.
- Private helpers accumulated at the bottom of a controller, far from the
  one action that calls each of them.
- `// region` / docblock section banners partitioning a class into "Getters",
  "Helpers", "Internals", hiding size instead of extracting classes.
- Note: conventional class-member ordering (constants → properties →
  methods) is a style choice, not this smell. Flag the *distance* between a
  member and its only usage site, not the ordering itself.

### TS / React

- Module-level constants or types declared at the top of a file and used
  once, hundreds of lines below.
- Helper components or functions defined at the bottom of a file for a
  single use near the top (or vice versa).
- `let` declared early and assigned/used much later inside a long function.
- `//#region` folding markers partitioning a component file.
- Note: React's Rules of Hooks require hooks to be called unconditionally
  at the component's top level, and grouping them at the top is ordinary
  convention; neither is this smell by itself. The signal is a piece of
  state far from the only JSX or handler that touches it: extract a child
  component or custom hook to close the gap.

## Example

Translated from the upstream examples.

Smelly; the declaration and the loop it exists for are separated by
unrelated work:

```ts
const retries = 5;

authenticate();
loadFixtures();
// ... many lines of unrelated setup ...

for (let attempt = 0; attempt < retries; attempt++) {
  // ...
}
```

Solution; the declaration moves to the code that needs it:

```ts
authenticate();
loadFixtures();
// ... many lines of unrelated setup ...

const retries = 5;
for (let attempt = 0; attempt < retries; attempt++) {
  // ...
}
```

Smelly: region markers organizing distance instead of removing it:

```ts
//#region State
// ...
//#endregion

//#region Helpers
// ...
//#endregion
```

## Refactorings

- Remove the Code Smells, fix the underlying smell (often
  [Long Method](long-method.md) or [Clever Code](clever-code.md)) instead of
  hiding it behind regions and banners.

## Related smells

| Smell | Edge |
|---|---|
| [Obscured Intent](obscured-intent.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Regions

---

*Derivative work adapted from "Vertical Separation" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
