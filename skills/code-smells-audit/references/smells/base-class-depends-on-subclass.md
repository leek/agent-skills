# Base Class depends on Subclass

`Between · Object Oriented Abusers · Interfaces`

Inheritance is supposed to point one way: children know their parent, the
parent knows nothing about who extends it. When the base class reaches back
down: naming its own subclasses, branching on `instanceof`, listing the
concrete types it expects: the tree grows upside down and the components stop
being independently deployable. Every new child means editing the trunk, and a
change to one leaf can break every sibling that shares the branch, which is
[Shotgun Surgery](shotgun-surgery.md) waiting to happen. It also quietly
breaks Liskov substitution: if the parent has to know which child it is holding
before it can behave correctly, the child was never substitutable for the
parent in the first place. The smell usually appears when a piece of behaviour
is *almost* shared, so it gets hoisted into the base with a small per-subclass
adjustment bolted on, rather than left as an abstract method the children fill
in.

## Detection heuristics

### Agnostic

- The parent's source file imports, references, or type-hints its own
  descendants.
- `match`/`switch` on `static::class`, `get_class($this)`, or `this.constructor`
  inside a base-class method.
- `instanceof` (or an equivalent type test) against a child, used from the
  parent to pick behaviour.
- The base holds a registry, array, or enum enumerating every concrete subtype,
  so adding a subclass means editing the superclass.
- A cyclic dependency between the module that defines the base and the modules
  that define the children.
- The base class's own tests cannot run without instantiating concrete
  children.
- Git history shows the parent file changing in nearly every commit that adds
  or renames a subclass.

### PHP / Laravel

- An abstract base model, job, notification, or report whose methods branch per
  concrete class: `if ($this instanceof PayrollReport)`, or a `match
  (static::class)` picking a filename, queue, or recipient list.
- Single-table inheritance where the base model overrides `newFromBuilder()` or
  a static `make()` to `match` the `type` column onto its own child classes, 
  move that decision into a dedicated factory, or into Laravel's morph map
  (`Relation::enforceMorphMap()`), which is configuration held outside the
  hierarchy rather than knowledge inside the parent.
- A base class constant listing children (`protected const TYPES = [Sales::class,
  Payroll::class]`) used to validate or dispatch.
- Base `FormRequest` or `Controller` whose shared method adds rules, abilities,
  or middleware "only for" one named subclass.
- Namespaces that show the direction of the dependency at a glance:
  `App\Reports\Report` referencing `App\Reports\Sales\SalesReport`.
- The base is `abstract` yet has no `abstract` methods; the variation is
  handled by branching instead of by dispatch.

### TS / React

- A base class with a `static create(kind: Kind)` that `new`s its own
  subclasses, producing a circular ESM import; at runtime this surfaces as
  `TypeError: Class extends value undefined is not a constructor or null`
  because the child module loaded before the parent finished evaluating.
- Base-class methods narrowing with `instanceof Child` or a `this is Child`
  type predicate.
- A union type declared in the base module that must be widened for every new
  implementation (`type AnyReport = SalesReport | PayrollReport | ...`).
- A shared abstract component or HOC that inspects `displayName`, a `variant`
  prop, or a lookup map of concrete children defined in the base file.
- Barrel files that make the cycle invisible: the base imports from
  `./index.ts`, which re-exports the children, which import the base.

## Example

Authored for this card: upstream has no code example for this smell.

Smelly: the abstract parent knows the name of every report that extends it:

```php
abstract class Report
{
    abstract public function rows(): Collection;

    public function filename(): string
    {
        return match (static::class) {
            SalesReport::class => 'sales-'.$this->period().'.csv',
            PayrollReport::class => 'payroll-'.$this->period().'.xlsx',
            TaxReport::class => 'tax-'.$this->period().'.pdf',
        };
    }

    public function recipients(): array
    {
        return $this instanceof PayrollReport
            ? User::role('finance')->pluck('email')->all()
            : User::role('admin')->pluck('email')->all();
    }
}

final class SalesReport extends Report
{
    public function rows(): Collection
    {
        return Order::completed()->get();
    }
}
```

Solution; the varying pieces become abstract methods, so the parent declares
what it needs and each child answers for itself:

```php
abstract class Report
{
    abstract public function rows(): Collection;

    abstract public function filename(): string;

    /** @return list<string> */
    abstract public function recipients(): array;
}

final class SalesReport extends Report
{
    public function rows(): Collection
    {
        return Order::completed()->get();
    }

    public function filename(): string
    {
        return 'sales-'.$this->period().'.csv';
    }

    public function recipients(): array
    {
        return User::role('admin')->pluck('email')->all();
    }
}
```

Adding a fourth report now touches one new file and nothing else.

## Refactorings

None recorded upstream. Invert the dependency by hand: move every mention of a
concrete subclass out of the parent, push the varying behaviour down as an
abstract method for polymorphic dispatch, and where the parent was choosing
*which* child to build, hand that job to a factory or a registry configured
from outside the hierarchy, so the arrows only ever point upward.

## Related smells

| Smell | Edge |
|---|---|
| [Shotgun Surgery](shotgun-surgery.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Base Classes Depending on Their Derivatives

---

*Derivative work adapted from "Base Class depends on Subclass" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
