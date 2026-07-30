# Dead Code

`Between · Dispensables · Unnecessary Complexity`

Code the executor will never reach: a branch whose condition can no longer be
true, statements after an unconditional `return`, a `catch` for an exception
the body cannot throw, a private method with no callers, or a block someone
commented out "just in case" and never came back for. It costs nothing at
runtime, which is why it survives — the price is paid by every reader who has
to work out whether it is safe to touch, and by every refactoring that has to
carry it along. It usually arrives quietly: a way of working was replaced and
the old path was never removed, or a
[Speculative Generality](speculative-generality.md) was built for a future
that never came. Detecting it reliably takes tooling, because the hard cases
are not the obvious unreachable line but the module that is only reachable
from other dead code. The fix is always the same, and version control
remembers the deletion.

## Detection heuristics

### Agnostic

- Statements after an unconditional `return`, `throw`, `break`, or `exit` in
  the same block.
- A branch whose guard an earlier branch already caught, or a comparison
  against a status/enum value nothing produces any more.
- Commented-out blocks, often with a name or date attached and a promise to
  restore them.
- Private methods with no callers; exported symbols nobody imports;
  parameters that are never read.
- `catch` blocks for exception types the guarded code cannot raise.
- Coverage reports showing lines never executed by any test, and production
  telemetry showing a path never taken.
- Feature flags pinned on or off for so long that the other side is
  effectively deleted already.
- Whole files reachable only from other dead files — transitive death, the
  kind manual review misses.

### PHP / Laravel

- Routes in `routes/web.php` or `routes/api.php` — visible in
  `php artisan route:list` — pointing at controller actions no client, link,
  or form targets any more.
- Eloquent accessors, mutators, casts, and scopes referring to columns a
  later migration dropped or renamed.
- Config keys in `config/*.php` with no matching `config('…')` reader, and
  `.env` entries nothing consumes.
- Artisan commands and `Schedule` entries that still run nightly but write
  to a table nothing reads.
- Listeners, jobs, notifications, and mailables that are never dispatched
  because the event that triggered them stopped firing.
- Blade views, partials, and `resources/views/components` classes no longer
  reached by `@include`, `<x-…>`, or any `view()` call.
- Policy methods for abilities removed from the UI, still authorizing a
  screen that no longer exists.
- Middleware or bindings commented out in `bootstrap/app.php` or a service
  provider rather than removed.

### TS / React

- Exported components, hooks, and types with no importers — what `knip` or
  `ts-prune` reports, and what `noUnusedLocals` catches at file scope.
- Props declared in the type and destructured in the signature but never
  used in the body or the JSX.
- Branches gated on a constant flag (`if (FEATURE_X)` where `FEATURE_X` is
  now `false`), including the `else` half of a flag that is permanently on.
- Router entries pointing at page components nothing navigates to.
- State whose setter is never called, so every branch reading that state has
  exactly one outcome.
- Commented-out JSX left inside the tree as `{/* … */}`.
- API client methods for endpoints the server removed, still typed and
  exported.

## Example

Authored for this card — upstream has no code example for this smell.

Smelly — an unreachable branch, an orphaned private method, and a
commented-out block kept "just in case":

```php
final class SubscriptionStatus
{
    public function label(Subscription $subscription): string
    {
        if ($subscription->cancelled_at !== null) {
            return 'Cancelled';
        }

        return $subscription->trial_ends_at?->isFuture() ? 'Trialling' : 'Active';

        // Kept in case marketing wants the old wording back:
        // if ($subscription->legacy_plan) {
        //     return $this->legacyLabel($subscription);
        // }
    }

    public function isDunning(Subscription $subscription): bool
    {
        if ($subscription->status === 'past_due') {
            return true;
        }

        if ($subscription->status === 'past_due' && $subscription->retries > 3) {
            return true;
        }

        return false;
    }

    private function legacyLabel(Subscription $subscription): string
    {
        return $subscription->legacy_plan_name ?? 'Legacy';
    }
}
```

Solution — delete all three; the retry threshold in the unreachable branch
was never a real rule, and the git history holds the old wording:

```php
final class SubscriptionStatus
{
    public function label(Subscription $subscription): string
    {
        if ($subscription->cancelled_at !== null) {
            return 'Cancelled';
        }

        return $subscription->trial_ends_at?->isFuture() ? 'Trialling' : 'Active';
    }

    public function isDunning(Subscription $subscription): bool
    {
        return $subscription->status === 'past_due';
    }
}
```

The unreachable branch is the dangerous one: it reads like a rule the system
enforces, so the next reader will reason about retry counts that never
mattered.

## Refactorings

- Remove It

## Related smells

| Smell | Edge |
|---|---|
| [Speculative Generality](speculative-generality.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Dead Code" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
