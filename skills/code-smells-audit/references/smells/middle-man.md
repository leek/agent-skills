# Middle Man

`Between · Data Dealers · Message Calls`

A class whose methods mostly forward to another class. Encapsulation is meant
to buy something: a rule enforced, a name improved, several calls combined, 
and a delegator that buys none of it charges every reader an extra file to
open in return for no information. Fowler's rough test is that once half of a
class's methods are one-line delegations, the class has stopped earning its
keep; Mäntylä's objection is maintenance, since each method added to the
delegate has to be mirrored in every wrapper fronting it. It usually arrives
as an over-correction of [Message Chain](message-chain.md): hide delegate
applied at every hop until pass-throughs outnumber real behavior. Deleting the
wrapper is the standard cure and the standard risk, remove too many and the
chains grow back, which is why these two smells are judged against each other
rather than separately.

## Detection heuristics

### Agnostic

- Half or more of a class's public methods are single-line forwards to the
  same collaborator, adding no guard, no mapping, no naming.
- Adding a method to the delegate obliges you to add a matching one to the
  wrapper, and a caller waited on both.
- You could delete the class and repoint callers at the collaborator with
  purely mechanical edits.
- Understanding a call means opening two files and learning nothing in the
  first one.
- Wrapper method names simply restate the delegate's, so the indirection does
  not even improve vocabulary.
- Judge it against its opposite: if removing the hop reintroduces a long walk
  through intermediates, the wrapper was paying for itself after all.

### PHP / Laravel

- A `Service` class whose methods each forward to one repository call, with no
  rule, transaction, or transformation of their own.
- Repositories mirroring Eloquent one for one, `find()`, `all()`,
  `create()`, `update()`, so the abstraction adds a layer but no policy.
- A model growing an accessor per related attribute
  (`getCustomerNameAttribute()` returning `$this->customer->name`), so every
  new customer field means another forwarding accessor.
- Action or controller classes that only call a single method on an injected
  collaborator and return its result unchanged.
- Legitimate exceptions worth not flagging: framework facades and contracts
  exist to swap or fake implementations, and a wrapper that narrows a wide
  vendor API to the three methods you use is doing real work.

### TS / React

- Components that only spread props onto one child, `<Button {...props} />`, 
  with no defaults, styling, or behavior added.
- Custom hooks whose entire body is `return useContext(SomeContext)`,
  multiplied across a dozen contexts.
- API modules where each function forwards to `http.get(url)` without adding
  types, error handling, or a retry policy.
- A context provider whose value is another provider's value, passed straight
  through.
- Wrapper types or re-export shims that only rename an import, so navigating
  to a definition takes two jumps.

## Example

Translated from the upstream Python example.

Smelly: `Minion` and `Location` both exist here only to forward the same
question down one more level:

```php
final class Minion
{
    private Location $location;

    public function action(): void
    {
        // ...
        if ($this->isFrontline()) {
            // ...
        }
    }

    public function isFrontline(): bool
    {
        return $this->location->isFrontline();
    }
}

final class Location
{
    private Field $field;

    public function isFrontline(): bool
    {
        return $this->field->isFrontline();
    }
}

final class Field
{
    public function isFrontline(): bool
    {
        // ...
    }
}
```

Solution: drop the pass-throughs and let the caller ask the object that
actually knows:

```php
final class Minion
{
    private Location $location;

    public function action(): void
    {
        // ...
        if ($this->location->field->isFrontline()) {
            // ...
        }
    }
}

final class Location
{
    public Field $field;
}

final class Field
{
    public function isFrontline(): bool
    {
        // ...
    }
}
```

Note the trade: this "solution" is precisely the smelly form of
[Message Chain](message-chain.md). Which one you accept depends on how many
hops there are and how likely the intermediate structure is to change.

## Refactorings

- Remove Middle Man
- Inline Method
- Replace Delegation with Inheritance
- Replace Superclass with Delegate

## Related smells

| Smell | Edge |
|---|---|
| [Global Data](global-data.md) | family |
| [Message Chain](message-chain.md) | antagonistic |
| [Tramp Data](tramp-data.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Middle Man" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
