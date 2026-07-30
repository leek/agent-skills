# Duplicated Code

`Within · Dispensables · Duplication`

The same knowledge expressed in more than one place. Fowler calls it the
worst smell in a codebase, and the cost is paid on every change: before you
can edit one copy you have to find the others, diff them closely enough to be
sure they are really the same, and then decide whether the change belongs to
one of them or all of them. Exact clones are the cheap case. The expensive
case is the near-copy that drifted — a missing guard, a different constant,
one branch someone fixed and the rest nobody did — because the divergence is
invisible until it produces a bug report from only one code path.

## Detection heuristics

### Agnostic

- The same statement sequence appears in two or more places, so a change to
  the rule means hunting down every copy.
- Near-copies with small differences you cannot immediately explain — that is
  where the drift, and the [Oddball Solution](oddball-solution.md), hides.
- Sibling subclasses whose method bodies are identical: candidates for
  pulling up.
- A bug you already fixed reappears in a later report, reached through a
  different entry point.
- Copy-paste fingerprints: identical comment wording or identical local
  variable names in modules that share nothing else.

### PHP / Laravel

- The same query constraints (`->where('status', 'active')->whereNull(
  'archived_at')`) inlined across several controllers instead of one Eloquent
  scope or a query builder method.
- Validation rule arrays repeated in multiple FormRequests, an Artisan
  command, and an API controller rather than shared through a rule object or
  a static `rules()` method.
- Blade markup pasted with a few tokens changed instead of one component with
  props and slots.
- An authorization rule re-implemented in a controller, a policy, and a Blade
  `@can` — three copies that can disagree.
- Pest or PHPUnit tests repeating the same arrange block in every case
  instead of a factory state, a shared dataset, or `beforeEach()`.

### TS / React

- Two components rendering nearly the same markup under different prop names.
- Fetch plus loading plus error orchestration inlined in several components
  rather than one custom hook or one shared query wrapper.
- Formatting and derivation logic (currency, dates, sort comparators)
  redefined per file instead of imported from one module.
- TS types redeclared field-for-field in several modules instead of imported,
  so they drift without the compiler noticing.
- The same `useEffect` subscription and cleanup wiring repeated across
  components.

## Example

Authored for this card — upstream has no code example for this smell.

Smelly:

```php
final class InvoiceController
{
    public function show(Invoice $invoice): View
    {
        $subtotal = $invoice->lines->sum(fn (Line $line) => $line->unit_price * $line->quantity);
        $tax = (int) round($subtotal * $invoice->customer->tax_rate);

        return view('invoices.show', [
            'invoice' => $invoice,
            'total' => $subtotal + $tax,
        ]);
    }
}

final class SendInvoiceReminder implements ShouldQueue
{
    public function handle(Invoice $invoice): void
    {
        $subtotal = $invoice->lines->sum(fn (Line $line) => $line->unit_price * $line->quantity);
        $tax = (int) ($subtotal * $invoice->customer->tax_rate);

        Mail::to($invoice->customer)->send(new ReminderMail($invoice, $subtotal + $tax));
    }
}
```

The second copy truncates where the first rounds — the reminder email quotes
a total the invoice page never shows, and nothing in the code says which one
is correct.

Solution — the rule gets one home, and the copies become calls:

```php
final class Invoice extends Model
{
    public function subtotal(): int
    {
        return $this->lines->sum(fn (Line $line) => $line->unit_price * $line->quantity);
    }

    public function tax(): int
    {
        return (int) round($this->subtotal() * $this->customer->tax_rate);
    }

    public function total(): int
    {
        return $this->subtotal() + $this->tax();
    }
}
```

Both call sites now read `$invoice->total()`, and the rounding rule has
exactly one place it can be wrong.

## Refactorings

- Extract Class
- Extract Method
- Pull Up Method
- Slide Statement
- Form Template Method

## Related smells

| Smell | Edge |
|---|---|
| [Alternative Classes with Different Interfaces](alternative-classes-with-different-interfaces.md) | co-exist |
| [Oddball Solution](oddball-solution.md) | co-exist |
| [Incomplete Library Class](incomplete-library-class.md) | caused |
| [Magic Number](magic-number.md) | caused |
| [Required Setup or Teardown Code](required-setup-or-teardown-code.md) | caused |
| [Type Embedded in Name](type-embedded-in-name.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Clones, Code Clone, Duplicate Code, Common Methods in Sibling Class, External
Duplication

---

*Derivative work adapted from "Duplicated Code" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
