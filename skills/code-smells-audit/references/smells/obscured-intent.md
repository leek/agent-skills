# Obscured Intent

`Between · Obfuscators · Unnecessary Complexity`

Code whose purpose you cannot recover by reading it. Martin's point in *Clean
Code* is that compactness is no defence: a four-line function can be as
impenetrable as a four-hundred-line one when nothing in it names what it is
for. This smell is rarely a defect on its own — it is what the other
Obfuscators add up to. Put an [Uncommunicative Name](uncommunicative-name.md)
next to a [Magic Number](magic-number.md), fold in an
[Imperative Loop](imperative-loops.md) and a
[Complicated Boolean Expression](complicated-boolean-expression.md), spread
the pieces apart with [Vertical Separation](vertical-separation.md), and pile
[Primitive Obsession](primitive-obsession.md) on top, and the meaning is gone
even though every individual line is legal and correct. The usual response
makes it worse: someone writes a ["What" Comment](what-comment.md) explaining
the code in prose, which freezes the confusion in place and starts drifting
from the code the moment it changes. It differs from its family sibling
[Clever Code](clever-code.md) in that Clever Code can be understood and still
annoys; Obscured Intent cannot be understood at all. The fix is not to explain
it but to remove the smells underneath until the code explains itself.

## Detection heuristics

### Agnostic

- You can describe what the code *does* mechanically but not what it is
  *for*, and reconstructing the purpose means reading every call site.
- Abbreviated or encoded identifiers — `m_ot_calc`, `i_ths_rte`, `tmp2`,
  `flag3` — where the domain has real words available.
- Unexplained constants embedded in arithmetic or comparisons, especially
  ones that encode a unit or threshold (`400`, `0.5`, `86400`).
- A comment restating the expression below it, or an apologetic one
  (`// don't touch`, `// magic`, `// this works, don't ask`).
- Dense formatting: several operations per line, continuation lines split
  mid-expression, no whitespace grouping the phases of a calculation.
- Everyone routes around it — bugs get patched at the edges rather than
  inside, and the file has one author and no reviewers on recent commits.
- The test suite covers it by asserting known input/output pairs nobody can
  explain, so nobody can tell a bug fix from a behavior change.

### PHP / Laravel

- Methods named for their mechanics rather than the rule they encode:
  `calc()`, `process()`, `doIt()`, `handleData()` on a domain class.
- Arithmetic over primitive money or duration values — cents, minutes,
  tenths of an hour — with the unit visible only in a variable name, if at
  all, where a small value object would carry it.
- Query builder chains assembled across many lines of `->where()` with raw
  column names and literal codes (`->where('t', 2)`), instead of a named
  local scope like `scopeOverdue()` that states the rule once.
- Long `when()`/`unless()` closure chains on a builder or collection, so the
  condition set is only discoverable by executing it mentally.
- Config or `.env` keys read inline in business logic with no name for what
  they mean, so the rule is split between code and deployment.
- Blade views computing domain rules inline — nested ternaries in an
  attribute, or `@if` conditions combining four unrelated model fields.
- Jobs and listeners whose class names describe timing rather than intent
  (`NightlyJob`, `AfterSaveListener`), leaving the actual rule buried in
  `handle()`.

### TS / React

- Single-letter or index-suffixed identifiers surviving outside a two-line
  callback: `d`, `x2`, `res2`, `data1`.
- Bit-level or numeric tricks standing in for domain concepts — flag masks
  on a status field, `Date` arithmetic in raw milliseconds, coordinate math
  with unnamed offsets.
- Components whose props are booleans and numbers with no names for the
  states they select (`<Chart mode={2} compact dense />`).
- `useEffect` blocks with opaque dependency arrays where the effect's purpose
  can only be inferred from which values retrigger it.
- Chained transforms with intermediate names like `filtered2`, `mapped`,
  `finalData` — the sequence is visible, the goal is not.
- Types that describe shape without meaning: `Record<string, any>`,
  `[number, number, string]` tuples passed between modules where a named
  interface would say what the slots are.

## Example

Translated from the upstream Python example — Robert Martin's overtime
calculation. (Upstream pairs it with a C++ block, the Quake III fast inverse
square root, not reproduced here; upstream shows no solution for either.)

Smelly — correct, compact, and unreadable: the names are encoded, the
thresholds are unexplained, and the expression is split mid-operator:

```php
final class Payroll
{
    private int $i_ths_wkd = 0;

    private int $i_ths_rte = 0;

    public function m_ot_calc(): int
    {
        return $this->i_ths_wkd * $this->i_ths_rte
            + (int) round(0.5 * $this->i_ths_rte
                * max(0, $this->i_ths_wkd - 400));
    }
}
```

Solution — nothing about the arithmetic changed; the names, the constants, and
the split into two phases are what carry the intent:

```php
final readonly class Timesheet
{
    private const int STANDARD_TENTHS = 400;

    private const float OVERTIME_MULTIPLIER = 0.5;

    public function __construct(
        private int $tenthsWorked,
        private int $tenthRate,
    ) {
    }

    public function pay(): int
    {
        return $this->basePay() + $this->overtimePay();
    }

    private function basePay(): int
    {
        return $this->tenthsWorked * $this->tenthRate;
    }

    private function overtimePay(): int
    {
        $overtimeTenths = max(0, $this->tenthsWorked - self::STANDARD_TENTHS);

        return (int) round(
            self::OVERTIME_MULTIPLIER * $this->tenthRate * $overtimeTenths,
        );
    }
}
```

This is why the refactoring is named the way it is: there is no single move
that fixes Obscured Intent, only the removal of the smells composing it.

## Refactorings

- Remove the Code Smells

## Related smells

| Smell | Edge |
|---|---|
| [Clever Code](clever-code.md) | family |
| [Uncommunicative Name](uncommunicative-name.md) | caused |
| [Magic Number](magic-number.md) | caused |
| [Loops](imperative-loops.md) | caused |
| [Complicated Boolean Expression](complicated-boolean-expression.md) | caused |
| [Primitive Obsession](primitive-obsession.md) | caused |
| [Vertical Separation](vertical-separation.md) | caused |
| ["What" Comments](what-comment.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Obscured Intent" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
