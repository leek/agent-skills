# Refactoring-Name Normalization Map

Upstream's `refactors` frontmatter uses 103 distinct names containing casing
variants, singular/plural variants, Fowler 1st-vs-2nd-edition renames, and a
few composite names. Cards use only **canonical** names from this map: every
upstream `refactors` entry is translated through the table below before it is
written onto a card.

Normalization policy:

- Where two names denote the same refactoring across Fowler editions
  (Extract Method / Extract Function), the canonical name is the one used by
  IDE refactoring tooling in this skill's target stacks (PhpStorm, VS Code), 
  the classic *Method* form. Where only the 2nd edition names the refactoring
  (Combine Functions into Class), its name stands.
- Composite upstream names (`Move Method and Move Field`) expand to multiple
  canonical names.
- Names unique in meaning keep their upstream spelling, even vague ones
  (`Remove It`, `Remove the Code Smells`).
- Overlapping-but-established entries stay distinct: `Change Method
  Declaration` subsumes `Rename Method` and `Reorder Parameters` in Fowler's
  2nd edition, but all three are kept because cards cite them with different
  intent. Likewise `Simplify Conditional` vs `Consolidate Conditional
  Expression`, and `Use Promises` vs `Use Asynchronous Functions` (distinct
  migration steps).

Result: 103 upstream names → **86 canonical names** (14 variants collapsed,
5 composites expanded; expansion introduces `Replace Subclass with Delegate`
and `Replace Type Code with State/Strategy`, which upstream only names inside
composites).

## Mapping table

`=` means the upstream name is already canonical.

| Upstream name | Canonical name(s) |
|---|---|
| Change Bidirectional Association to Unidirectional | = |
| Change Method Declaration | = |
| Change Reference to Value | = |
| Choose Proper Access Control | = |
| Collapse Hierarchy | = |
| Combine Functions into Class | = |
| Combine Functions into Transform | = |
| Combine Methods into Class | Combine Functions into Class |
| Consolidate Conditional Expression | = |
| Create Partial | = |
| Encapsulate Collection | = |
| Encapsulate Field | = |
| Encapsulate Variable | Encapsulate Field |
| Extract Class | = |
| Extract Conditional | = |
| Extract Domain Object | = |
| Extract Field | = |
| Extract Function | Extract Method |
| Extract Interface | = |
| Extract Method | = |
| Extract Methods | Extract Method |
| Extract method | Extract Method |
| Extract Subclass | = |
| Extract Superclass | = |
| Extract Variable | = |
| Fold Hierarchy into One | Collapse Hierarchy |
| Form Template Method | = |
| Freeze Variables | = |
| Hide Behind Abstract Class | = |
| Hide Behind Interface | = |
| Hide Behind Method | = |
| Hide Delegate | = |
| Inject Dependencies | = |
| Inline Class | = |
| Inline Function | Inline Method |
| Inline Function/Class | Inline Method + Inline Class |
| Inline Method | = |
| Introduce Assertion | = |
| Introduce Explaining Method or Variable | Extract Method + Extract Variable |
| Introduce Foreign Method | = |
| Introduce Linter Rules | = |
| Introduce Local Extension | = |
| Introduce Maybe | Introduce Optional |
| Introduce New Type | = |
| Introduce Null Object | = |
| Introduce Optional | = |
| Introduce Parameter Object | = |
| Move Embellishment to Decorator | = |
| Move Field | = |
| Move Function | Move Method |
| Move Method | = |
| Move Method and Move Field | Move Method + Move Field |
| Preserve the Whole Object | = |
| Pull Up Method | = |
| Push Down Field | = |
| Push Down Method | = |
| Remove Flag Argument | = |
| Remove Inconsistency | = |
| Remove It | = |
| Remove Middle Man | = |
| Remove Setting Method | = |
| Remove Status Variables | = |
| Remove the Code Smells | = |
| Rename Field | = |
| Rename Method | = |
| Rename Variable | = |
| Reorder Parameters | = |
| Replace Array with Object | = |
| Replace Conditional with Polymorphism | = |
| Replace Constructor with Factory Method | = |
| Replace Data Value with Object | = |
| Replace Data Value with object | Replace Data Value with Object |
| Replace Delegation with Inheritance | = |
| Replace Derived Variable with Query | = |
| Replace Exception with Test | = |
| Replace Inheritance with Delegation | = |
| Replace Loop with Pipeline | = |
| Replace Loop with built-in | Replace with Built-In |
| Replace Method with Command | = |
| Replace Parameter with Query | = |
| Replace Superclass with Delegate | = |
| Replace Superclass/Subclass with Delegate | Replace Superclass with Delegate + Replace Subclass with Delegate |
| Replace Type Code with Class | = |
| Replace Type Code/Conditional Logic with State/Strategy | Replace Type Code with State/Strategy |
| Replace with Built-In | = |
| Replace with Library | = |
| Replace with Parameter | = |
| Replace with Polymorphism | Replace Conditional with Polymorphism |
| Replace with Symbolic Constant | = |
| Separate Query from Modifier | = |
| Simplify Conditional | = |
| Slide Statement | = |
| Split Loop | = |
| Split Phase | = |
| Tease Apart Inheritance | = |
| Unify Interfaces with Adapter | = |
| Use Asynchronous Functions | = |
| Use Functional Programming Based Solution | = |
| Use Guard Clauses | = |
| Use Null Object | Introduce Null Object |
| Use Promises | = |
| Use Strategy Pattern | = |
| Use a Guard Clause | Use Guard Clauses |
