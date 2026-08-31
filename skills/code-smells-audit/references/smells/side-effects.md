# Side Effects

`Within · Functional Abusers · Responsibility`

A method that quietly does more than its name promises. `setGold($amount)`
assigns the gold, and also starts a dancing animation and resets the payday
timer, so the call site, which is exactly where a reader should be able to
skim and understand, tells them something untrue. The bill arrives during
debugging: behavior appears out of calls that looked inert, the order of two
innocuous statements starts to matter, and the method cannot be reused
anywhere the hidden extras are unwanted. It accretes rather than being
designed: someone needed the extra action at every call site that existed
that day, and bolting it on was cheaper than adding a second call. The honest
fix is to split the extras into their own named method and call it explicitly:
renaming to `setGoldAndResetPayday()` only trades this smell for
[Binary Operator in Name](binary-operator-in-name.md), and adding a
`bool $resetPayday` parameter trades it for [Flag Argument](flag-argument.md).

## Detection heuristics

### Agnostic

- A method named like a setter, getter, or question also writes, notifies, or
  mutates state its name never mentions.
- Call sites carry explanatory comments about what else the call does, or the
  team knows a "you also have to call it before X" rule by folklore.
- Asking the same question twice gives different answers, or reordering two
  adjacent calls changes the result.
- Testing the method means asserting on state the name does not mention, or
  stubbing collaborators it should never have touched.
- The proposed rename contains "and", and the proposed alternative is a
  boolean parameter; both are the smell arguing for a disguise.

### PHP / Laravel

- An Eloquent accessor or mutator that does more than transform a value, 
  touching related records, dispatching a job, or writing to the cache.
- A getter-shaped method that lazily persists: `getSettings()` implemented
  with `firstOrCreate()`, so reading creates a row.
- Model event hooks (`saving`, `saved`) in an observer or `booted()`, so a
  plain `$model->save()` also mails, invalidates cache, and writes an audit
  record, none of it visible at the call site.
- A method named `calculateTotal()` or `buildInvoice()` that also saves the
  result, so you cannot preview a total without committing one.
- Facades reached mid-calculation, `Auth::user()`, `session()`,
  `Cache::forget()`: pulling ambient state into a method that reads pure.

### TS / React

- Work done during render or inside `useMemo`: fetching, writing
  `localStorage`, or calling a setter, so a value that reads as derivation is
  actually an effect.
- Selector or formatting helpers mutating what they receive, `.sort()` or
  `.reverse()` applied in place to a props array or store slice.
- A handler named `validate()` that also submits, or `useUser()` that also
  fires analytics and redirects on 401.
- Reducer cases that do more than return the next state, dispatching a
  request, writing to storage, or calling a router.
- An exported utility that both returns a value and updates module-level
  state, so importing it twice from different modules is not idempotent.

## Example

Translated from the upstream Python example.

Smelly: `setGold()` also animates and resets a timer, so the three-line call
site does five things:

```php
final class Player
{
    public function __construct(
        public int $gold,
        private Job $job,
    ) {
    }

    public function setGold(int $amount): void
    {
        $this->gold = $amount;
        $this->triggerAnimation(Animation::Dancing);
        $this->job->resetPaydayTimer();
    }
}

$marcel = Player::findByName('Marcel', 'Jerzyk');
$marcel->setGold(0);
$marcel->setHealth(Health::Decent);
```

Solution; the payday behavior gets its own name and is triggered on purpose:

```php
final class Player
{
    public function __construct(
        public int $gold,
        private Job $job,
    ) {
    }

    public function setGold(int $amount): void
    {
        $this->gold = $amount;
    }

    public function payoutRoutine(): void
    {
        $this->triggerAnimation(Animation::Dancing);
        $this->job->resetPaydayTimer();
    }
}

$marcel = Player::findByName('Marcel', 'Jerzyk');
$marcel->setGold(0);
$marcel->payoutRoutine();
$marcel->setHealth(Health::Decent);
```

## Refactorings

- Extract Method
- Extract Field

## Related smells

| Smell | Edge |
|---|---|
| [Mutable Data](mutable-data.md) | caused |
| [Dubious Abstraction](dubious-abstraction.md) | causes |
| [Binary Operator in Name](binary-operator-in-name.md) | antagonistic |
| [Flag Arguments](flag-argument.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Impure Functions

---

*Derivative work adapted from "Side Effects" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
