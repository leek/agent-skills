# Feature Envy

`Between · Couplers · Responsibility`

A method that spends more of its attention on another object's fields and
methods than on its own. Behavior belongs next to the data it works with; a
method that keeps reaching across the boundary is telling you it was written
in the wrong place and is more tightly bound to the class it envies than to
the one hosting it. Fowler later restated this in terms of modules rather
than classes, so the same reading applies at whatever zone size the system
is organised by. The root cause is misplaced responsibility, and the costs
compound: the method cannot be tested without constructing or mocking the
envied object, it cannot be reused without dragging that object along, and
the code drifts away from the domain it models, since the concept that
"knows" this rule in conversation is not the one that implements it.

## Detection heuristics

### Agnostic

- Another object's name appears in the body more often than the host's own
  state does.
- Long runs of accessor calls on one collaborator feeding a local
  calculation, with nothing of the host's own involved.
- Moving the method onto the envied class would shrink its parameter list to
  nothing, a strong signal about where it belongs.
- Testing the method in isolation is impossible; the envied object must be
  built or mocked first.
- Several methods across different classes all reach into the same object
  for the same fields (see [Insider Trading](insider-trading.md) and
  [Fate over Action](fate-over-action.md)).

### PHP / Laravel

- Service or action classes computing over a model's relations, 
  `$order->lines->sum(fn ($line) => $line->price * $line->quantity)`: where
  an accessor or a method on the model or its collection would own the rule.
- Blade views and Filament columns assembling values from raw attributes
  (`$user->first_name.' '.$user->last_name`, status-to-colour maps) instead
  of calling an accessor the model exposes.
- Observers and listeners reading and writing several attributes on the
  subject model to enforce a rule the model could enforce for itself.
- Policies walking a chain of relations (`$post->author->team->plan->tier`)
  to reach a verdict the far object should be asked for directly, Feature
  Envy arriving alongside [Message Chain](message-chain.md).
- Jobs whose payload is an entity they immediately take apart, using its
  fields rather than asking it to do anything.

### TS / React

- Components deriving formatted strings, totals, or badge state from a prop
  entity's fields, rather than calling something the entity module exposes.
- Helper functions whose only parameter is an object they immediately
  destructure and recombine, a method on that object in disguise.
- Selectors or hooks reaching deep into another store slice's shape, which
  then break whenever that slice is reorganised.
- Event handlers that read and write several fields of a passed-in object
  instead of dispatching an action to the module that owns it.

## Example

Translated from the upstream Python example.

Smelly: `Order` never touches its own state; every line computes from a
`ShoppingItem`'s fields:

```php
final class ShoppingItem
{
    public function __construct(
        public readonly string $name,
        public readonly float $price,
        public readonly float $tax,
    ) {
    }
}

final class Order
{
    /** @param list<ShoppingItem> $items */
    public function billTotal(array $items): float
    {
        return array_sum(array_map(
            fn (ShoppingItem $item): float => $item->price * $item->tax,
            $items,
        ));
    }

    /** @param list<ShoppingItem> $items */
    public function receiptLines(array $items): array
    {
        return array_map(
            fn (ShoppingItem $item): string => sprintf(
                '%s: %s$',
                $item->name,
                $item->price * $item->tax,
            ),
            $items,
        );
    }

    /** @param list<ShoppingItem> $items */
    public function createReceipt(array $items): string
    {
        return implode("\n", $this->receiptLines($items))
            ."\nBill: {$this->billTotal($items)}$";
    }
}
```

Solution: the taxed price and the line's own rendering move onto the item;
`Order` keeps only what is genuinely about the order:

```php
final class ShoppingItem
{
    public function __construct(
        public readonly string $name,
        public readonly float $price,
        public readonly float $tax,
    ) {
    }

    public function taxedPrice(): float
    {
        return $this->price * $this->tax;
    }

    public function receiptLine(): string
    {
        return sprintf('%s: %s$', $this->name, $this->taxedPrice());
    }
}

final class Order
{
    /** @param list<ShoppingItem> $items */
    public function billTotal(array $items): float
    {
        return array_sum(array_map(
            fn (ShoppingItem $item): float => $item->taxedPrice(),
            $items,
        ));
    }

    /** @param list<ShoppingItem> $items */
    public function createReceipt(array $items): string
    {
        $lines = array_map(
            fn (ShoppingItem $item): string => $item->receiptLine(),
            $items,
        );

        return implode("\n", $lines)."\nBill: {$this->billTotal($items)}$";
    }
}
```

## Refactorings

- Move Method
- Move Field
- Extract Method

## Related smells

| Smell | Edge |
|---|---|
| [Fate over Action](fate-over-action.md) | caused |
| [Insider Trading](insider-trading.md) | co-exist |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Feature Envy" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
