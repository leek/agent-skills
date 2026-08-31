# Long Method

`Within · Bloaters · Measured Smells`

A method that has grown past the point where a reader can hold it in their
head. Length is only the symptom you can measure; the underlying problem is
that the method contains several distinct steps or responsibilities that were
never given names of their own, so every change requires re-reading the whole
body, none of the trapped logic can be reused, and behavior the name never
promised can hide three screens below the signature. It usually grows one
innocent line at a time: adding a line to an existing method is always cheaper
in the moment than extracting a well-named helper.

## Detection heuristics

### Agnostic

- The body no longer fits on one screen. Common alarm thresholds sit around
  20–30 lines: treat any number as a prompt to look closer, not a verdict.
- Blank-line "paragraphs" or banner comments (`// validate`, `// persist`)
  partition the body into phases; each phase is an extraction waiting for a
  name.
- You cannot summarize what the method does without "and".
- Three or more levels of nested conditionals or loops.
- Local variables declared near the top and threaded through many later steps
  (see [Vertical Separation](vertical-separation.md)).

### PHP / Laravel

- Controller actions that validate, authorize, mutate models, fire events or
  notifications, and shape the response inline, work that belongs in a
  FormRequest, a policy, and an action/service class.
- A queued job's or Artisan command's `handle()` written as one long
  procedural script.
- Long closures handed to `DB::transaction()` or buried mid-way through a
  `Collection` chain, embedding business rules where they can't be tested or
  reused.
- Model observers, accessors, or event listeners that accreted multi-step
  workflows.

### TS / React

- Component function bodies mixing data fetching, transformation, event
  handlers, and hundreds of lines of JSX, each concern extractable into a
  custom hook or child component.
- `useEffect` callbacks that orchestrate multi-step logic inline instead of
  calling named functions.
- Event handlers that validate, call the API, update several pieces of state,
  and navigate, all in one closure.
- Reducers whose `switch` cases each contain full business logic rather than
  delegating to named functions.

## Example

Authored for this card: upstream has no code example for this smell.

Smelly:

```php
public function store(StoreOrderRequest $request): RedirectResponse
{
    $items = collect($request->validated('items'));

    $subtotal = 0;
    foreach ($items as $item) {
        $product = Product::findOrFail($item['product_id']);
        if ($product->stock < $item['quantity']) {
            return back()->withErrors(['items' => "{$product->name} is out of stock"]);
        }
        $subtotal += $product->price * $item['quantity'];
    }

    $discount = 0;
    if ($request->user()->orders()->count() === 0) {
        $discount = (int) round($subtotal * 0.10);
    } elseif ($subtotal >= 50_000) {
        $discount = (int) round($subtotal * 0.05);
    }

    $order = $request->user()->orders()->create([
        'subtotal' => $subtotal,
        'discount' => $discount,
        'total' => $subtotal - $discount,
    ]);
    foreach ($items as $item) {
        $order->lines()->create($item);
        Product::whereKey($item['product_id'])->decrement('stock', $item['quantity']);
    }

    Mail::to($request->user())->queue(new OrderConfirmation($order));

    return redirect()->route('orders.show', $order);
}
```

Solution; each phase extracted behind a name; the action reads as its own
summary:

```php
public function store(StoreOrderRequest $request): RedirectResponse
{
    $items = OrderItems::fromRequest($request);

    $order = $this->placeOrder->handle($request->user(), $items);

    Mail::to($request->user())->queue(new OrderConfirmation($order));

    return redirect()->route('orders.show', $order);
}
```

with a `PlaceOrder` action injected through the controller's constructor and
`PlaceOrder::handle()` delegating to `assertInStock()`, `discountFor()`, and
`createOrderLines()`: short methods whose names carry the rules the long
body used to bury.

## Refactorings

- Extract Method
- Replace Conditional with Polymorphism
- Replace Method with Command
- Introduce Parameter Object
- Preserve the Whole Object
- Split Loop

## Related smells

| Smell | Edge |
|---|---|
| [Large Class](large-class.md) | causes |
| [Side Effects](side-effects.md) | causes, co-exist |
| [Dubious Abstraction](dubious-abstraction.md) | co-exist |
| [Long Parameter List](long-parameter-list.md) | co-exist |
| [Flag Argument](flag-argument.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Complex Method, God Method, Brain Method

---

*Derivative work adapted from "Long Method" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
