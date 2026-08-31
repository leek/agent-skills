# Binary Operator in Name

`Within · Couplers · Names`

A method whose name contains a conjunction (`and`, `or`, `then`) is
confessing in public that it does two things, and that confession is the
easiest Single Responsibility violation there is to spot: no analysis
required, just read the identifier. An `and` says the body has two halves
that could each stand alone and be called separately. An `or` says worse:
two halves and something that picks between them, usually a
[Flag Argument](flag-argument.md) the caller has to know how to set. The
smell is not confined to methods, variables and classes carrying a
conjunction are bundling two concepts under one name for the same reason.

## Detection heuristics

### Agnostic

- `and`, `or`, `then`, `plus`, or a `&` / `/` separator in a function name.
- You cannot describe what the function does without the word "and".
- An `or` in the name paired with a boolean parameter that selects which half
  runs.
- Callers who want only one half pass a flag, or ignore half the return
  value, or immediately undo the other half.
- Variables and classes too, not only methods: `$userAndOrder`,
  `ImportAndValidate`.

### PHP / Laravel

- Action or service methods like `validateAndStore()`, `syncAndNotify()`,
  `parseAndImport()`: Extract Method splits them and the caller composes the
  two calls.
- Hand-rolled repository methods echoing framework naming
  (`findOrProvision()`, `fetchOrSeed()`); Eloquent's own `firstOrCreate()`
  earns the exception because the two branches are one atomic upsert, yours
  usually is not.
- Artisan commands bundling two verbs in the signature
  (`reports:build-and-send`); you can never re-run just the send after the
  mail driver fails.
- Model methods like `markPaidAndInvoice()` that mutate state and dispatch
  work in one call (see [Side Effects](side-effects.md)).
- Event listeners or observers named `handleAndLog()`, where the logging half
  belongs in its own listener on the same event.

### TS / React

- Hooks named `useFetchAndTransform()` or `useAuthAndRedirect()`: a hook
  that both loads data and navigates cannot be reused for either alone, and
  cannot be tested without a router.
- Handlers like `handleSubmitAndClose()`: closing the modal is the parent's
  concern, not the form's.
- Utility functions `parseAndValidate()` returning a tuple whose second
  element half the call sites discard.
- Component props named `onSaveAndContinue`: one callback standing in for
  two distinct events the parent may want to handle differently.
- Reducer action types like `FETCH_AND_STORE` whose case body has two
  unrelated state transitions.

## Example

Translated from the upstream Python example.

Smelly; the name promises two things, so no caller can have just one:

```php
public function renderAndSave(Invoice $invoice): string
{
    $html = view('invoices.pdf', ['invoice' => $invoice])->render();

    Storage::disk('invoices')->put("{$invoice->getKey()}.html", $html);

    return $html;
}
```

Solution: one responsibility per name; previewing an invoice no longer
writes a file as a side effect:

```php
public function render(Invoice $invoice): string
{
    return view('invoices.pdf', ['invoice' => $invoice])->render();
}

public function save(Invoice $invoice, string $html): void
{
    Storage::disk('invoices')->put("{$invoice->getKey()}.html", $html);
}
```

## Refactorings

- Extract Method

## Related smells

| Smell | Edge |
|---|---|
| [Flag Argument](flag-argument.md) | causes |
| [Status Variable](status-variable.md) | co-exist |
| [Side Effects](side-effects.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic. The antagonistic edge records a trade-off: naming
both halves is honest about the side effect, and splitting the method to
remove the conjunction can leave the second call easy for a caller to forget.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Binary Operator in Name" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
