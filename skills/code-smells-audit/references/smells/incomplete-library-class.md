# Incomplete Library Class

`Between · Other · Interfaces`

A dependency does almost everything you need, and then stops one method short.
You cannot fix it at the source — the maintainers are volunteers with their own
roadmap, the method you need is `private` or `final`, or the pull request would
take months — so the gap gets filled locally. The smell is not the gap itself;
it is how the gap gets filled. Left unmanaged, each call site invents its own
workaround, and the same three lines appear in five files in four slightly
different versions, which is [Duplicated Code](duplicated-code.md) with drift
built in. The alternative failure mode is one heroic workaround that reaches
into the library's internals by reflection, patching, or type gymnastics —
[Clever Code](clever-code.md) that breaks on the next minor release. The
disciplined answers are small and old: add the missing method as a foreign
method attached to the library's own surface, or wrap the library in a thin
local extension you own, so the gap is filled once, in one place, with one
test.

## Detection heuristics

### Agnostic

- The same small fix-up appears around a library call in several files, each
  version subtly different from the others.
- A comment naming the library and its shortcoming: "X doesn't support Y, so
  we…", usually next to a link to an open issue.
- A vendored, forked, or patched copy of a dependency lives in the repository
  for the sake of one behaviour.
- Reflection, prototype patching, or access to underscore-prefixed internals to
  reach something the public API withholds.
- The dependency is pinned to an old version because the workaround breaks on
  upgrade, and nobody remembers which workaround.
- A feature the library already provides has been reimplemented alongside it,
  because the built-in version was 90% right.

### PHP / Laravel

- The same `Str::` / `Arr::` / `Collection` pipeline copy-pasted across
  controllers, jobs, and mailables because the framework has no single call for
  it — the missing operation wants to be a macro.
- Laravel's `Macroable` surfaces are where Introduce Foreign Method lives:
  `Str`, `Arr`, `Collection`, `Request`, the response factory, the query and
  Eloquent builders, and `TestResponse` all accept `::macro()` registered from
  a service provider's `boot()`.
- A subclass of a vendor class that copy-pastes the parent's method body to
  change three lines, because the real hook is `private` or `final`.
- Local extension done properly: your class wraps or extends the vendor class,
  and the container is told to hand yours out
  (`$this->app->bind(VendorClient::class, LocalClient::class)`), so call sites
  never learn the difference.
- Entries in `composer.json` for a patch tool such as
  `cweagans/composer-patches`, or a `patches/` directory — legitimate, but each
  patch is an unpaid debt that must be re-applied on every upgrade.
- `@method` docblocks or `Reflection` used to reach a package's protected
  state, so static analysis passes while the coupling is invisible.

### TS / React

- `patch-package` entries in `package.json` scripts, or a `patches/` folder
  checked into the repo.
- Module augmentation (`declare module 'x'`) or prototype patching used to bolt
  behaviour onto a third-party type at runtime.
- A `lib/<library>-helpers.ts` module that keeps growing — this is the right
  shape (one home for the foreign methods) and only smells once copies of the
  same helper also exist inline at call sites.
- `as any` / `as unknown as T` casts clustered around one library's API, hiding
  an option or return shape the types do not expose.
- A hook or component lifted out of a library's source into your tree to change
  one line, then left to drift from upstream.
- Wrapper components that reimplement a UI library's behaviour instead of
  composing it: the good version forwards props and refs and adds only the
  missing piece.

## Example

Authored for this card — upstream has no code example for this smell.

Smelly — `Str` has no `initials` helper, so each caller invents one and they
disagree on the edge cases:

```php
final class InvoiceController
{
    public function show(Invoice $invoice): View
    {
        $initials = collect(explode(' ', $invoice->customer_name))
            ->take(2)
            ->map(fn (string $part): string => Str::upper(Str::substr($part, 0, 1)))
            ->implode('');

        return view('invoices.show', compact('invoice', 'initials'));
    }
}

final class InvoiceReminderMail extends Mailable
{
    public function content(): Content
    {
        $parts = explode(' ', $this->invoice->customer_name);
        $initials = strtoupper($parts[0][0].($parts[1][0] ?? ''));

        return new Content('mail.invoice-reminder', with: ['initials' => $initials]);
    }
}
```

Solution — the missing method is introduced onto the library's own surface once,
in a service provider, and every caller uses it:

```php
final class AppServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        Str::macro('initials', function (string $name, int $limit = 2): string {
            return collect(preg_split('/\s+/', trim($name), -1, PREG_SPLIT_NO_EMPTY))
                ->take($limit)
                ->map(fn (string $part): string => Str::upper(Str::substr($part, 0, 1)))
                ->implode('');
        });
    }
}

// every caller now shares one implementation, with one place to test it
$initials = Str::initials($invoice->customer_name);
```

A macro is Introduce Foreign Method in Laravel's vocabulary — right for one or
two additions. Once the gap needs several related methods, or the behaviour
deserves its own type and IDE support, promote it to a small class you own
(Introduce Local Extension) and bind it in the container.

## Refactorings

- Introduce Foreign Method
- Introduce Local Extension

## Related smells

| Smell | Edge |
|---|---|
| [Duplicated Code](duplicated-code.md) | causes |
| [Clever Code](clever-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Incomplete Library Class" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
