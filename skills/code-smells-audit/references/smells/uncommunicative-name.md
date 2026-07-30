# Uncommunicative Name

`Within · Lexical Abusers · Names`

A name that forces the reader to open the implementation to learn what the
thing holds or does. Abbreviations only the author can expand, placeholders
like `data` and `temp`, numbered siblings, and method names that describe
machinery rather than the rule — each shifts work from the one moment the name
was chosen onto every future reader. Names are usually the best they could be
at the instant of declaration and are almost never revisited once the code
around them teaches the author what they actually mean; the cost is paid
silently, in the extra glossary every reader has to build before the code
makes sense.

## Detection heuristics

### Agnostic

- Understanding a line requires jumping to a definition to decode a name.
- Abbreviations and placeholders: `tmp`, `val`, `res`, `m1`, `calc`, `getF`.
- Numbered siblings — `data`, `data2`, `value`, `val` — where the number is
  the only thing distinguishing two concepts.
- The name states the container or type rather than the meaning, which
  overlaps with [Type Embedded in Name](type-embedded-in-name.md).
- The name promises less than the code delivers: a `get`-shaped method that
  also writes, so the side effect is invisible at the call site.
- A comment exists purely to translate the name into English.

### PHP / Laravel

- Locals threaded through a controller or service as `$data`, `$res`,
  `$temp`, `$arr`, where the value has a perfectly good domain name
  (`$overdueInvoices`).
- Jobs, listeners, and Artisan commands named for machinery rather than the
  rule they enforce — `ProcessJob`, `SyncData`, a signature of `app:run` —
  where the command signature is the only documentation an operator sees.
- Accessors and query scopes named for mechanism (`getDataAttribute()`,
  `scopeFilter()`), which read as `$user->data` and `Order::filter()` at call
  sites far from any definition that would explain them.
- Migration columns abbreviated past recognition (`usr_st`, `amt2`, `flg`),
  pushing the decoding into every query, factory, and Blade view that touches
  them.
- Pest or PHPUnit tests named `it('works')` or `test_example` — a failing run
  then names nothing about which rule broke.

### TS / React

- Params and locals named `data`, `res`, `item`, `val`, `x`, especially
  API responses destructured and passed onward unchanged.
- Handlers named for the event instead of the intent — `handleClick`,
  `handleChange2` — where `saveDraft` or `applyCoupon` states the rule.
- Custom hooks named after their plumbing (`useData`, `useFetch`) rather than
  the concept they return (`useOverdueInvoices`).
- Single-letter or numbered generics (`T`, `T2`) on an exported type, where a
  bound name (`TRow`, `TPayload`) would document the constraint at every use.
- Boolean props and state named ambiguously (`flag`, `status`, `ok`), leaving
  the reader to discover which state `true` means — a close cousin of
  [Boolean Blindness](boolean-blindness.md).

## Example

Translated from the upstream Python example.

Smelly — every name is a placeholder, and the `3` is unexplained too:

```ts
const data = m1.getF();
const data2 = m2.getF();

const value = data2.dmg * data.def;
const val = rand(value - 3, value + 3);
```

Solution — each name states its concept, and the nameless helper becomes a
named function whose call site explains its own arguments:

```ts
function wobbleValue(value: number, { by }: { by: number }): number {
  return rand(value - by, value + by);
}

const attackStats: FightingStats = attackingMinion.fightingStats();
const defenseStats: FightingStats = defendingMinion.fightingStats();

const calculatedDamage = attackStats.damage * defenseStats.defense;
const finalDamageDealt = wobbleValue(calculatedDamage, { by: 3 });
```

## Refactorings

- Change Method Declaration
- Rename Variable
- Rename Field

## Related smells

| Smell | Edge |
|---|---|
| [Magic Number](magic-number.md) | family |
| [Boolean Blindness](boolean-blindness.md) | family |
| [Type Embedded in Name](type-embedded-in-name.md) | co-exist |
| [Obscured Intent](obscured-intent.md) | causes |
| ["What" Comment](what-comment.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Mysterious Name, Function Names Should Say What They Do, Choose Descriptive
Names, Ambiguous Name

---

*Derivative work adapted from "Uncommunicative Name" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
