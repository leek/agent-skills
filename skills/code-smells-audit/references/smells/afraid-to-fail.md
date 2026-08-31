# Afraid To Fail

`Within · Couplers · Responsibility`

Code that refuses to admit failure, handing back a status code, a boolean
flag, or a bare null that the caller is expected to remember to inspect. The
check that belonged inside the callee gets pushed outward, so every call site
grows the same defensive `if`, and the return type stops describing the
result and starts describing the envelope around it. That is real coupling:
the caller cannot use the value until it has re-derived what went wrong, and
a caller who forgets the check carries a broken value deeper into the system
until it surfaces somewhere unrelated. It comes from a well-meant reluctance
to interrupt the flow: throwing feels rude, and silence usually gets away
with it, but the Fail Fast principle wants the opposite: report at the point
of failure, either by throwing or by returning a Null Object of the expected
type, never a status the caller has to decode.

## Detection heuristics

### Agnostic

- Functions return "status plus maybe a value", a tuple, a dict, a wrapper
  struct, rather than the value the name promises.
- Every call site repeats the same success check before it can touch the
  result, and the checks drift apart over time.
- The return type is a union of the real result and a sentinel (`null`,
  `false`, `-1`, empty string), which forces a [Null Check](null-check.md) at
  each caller.
- The caller reconstructs, from a code or a flag, information the callee
  already had in full.
- Boilerplate accretes around every call to unwrap and re-check the result
  (see [Required Setup or Teardown Code](required-setup-or-teardown-code.md)).
- Deleting one caller's check changes nothing visible until much later, 
  failures are silent, not loud.

### PHP / Laravel

- Service methods returning `['ok' => bool, 'data' => ...]` instead of
  throwing a domain exception, when Laravel's exception handler already turns
  a thrown exception into the right response.
- `Model::find()` used where `findOrFail()` is meant, so the null travels into
  the controller (or into the Blade view) before anyone notices.
- `Http::get(...)` responses passed around for callers to test with
  `$response->successful()`, when `->throw()` at the call site would raise a
  `RequestException` at the point of failure.
- Hand-rolled validation helpers returning an array of errors for callers to
  inspect, instead of a FormRequest or `validate()` throwing
  `ValidationException`.
- Queued jobs that catch an exception, log it, and `return`: the queue
  records success, so retries and the job's `failed()` hook never run.

### TS / React

- Functions typed `Promise<{ ok: boolean; data?: T; error?: string }>` where
  every caller destructures and branches before it can use `data`.
- API wrappers that `catch` and return `null`, pushing a null check into every
  component that renders the result.
- `T | undefined` used for both "not found" and "request failed", so callers
  cannot distinguish the two and treat both as empty.
- Hooks exposing an `error` field that no consumer reads, because nothing in
  the types forces them to.
- `try`/`catch` around an `await` that logs and continues with a
  half-initialized value instead of rethrowing to an error boundary.

## Example

Translated from the upstream Python example.

Smelly; the status code rides along with the value, and the caller has to
unpack both:

```php
function createFoo(): array
{
    $response = Http::get('https://api.github.com/events');

    if ($response->failed()) {
        return ['status' => $response->status(), 'foo' => null];
    }

    return ['status' => $response->status(), 'foo' => new Foo($response->json())];
}

$fooResponse = createFoo();

if ($fooResponse['status'] === 200) {
    $foo = $fooResponse['foo'];
}
```

Solution: fail at the point of failure, so the signature can promise a `Foo`
and the caller has nothing to check:

```php
function createFoo(): Foo
{
    $response = Http::get('https://api.github.com/events')->throw();

    return new Foo($response->json());
}

$foo = createFoo();
```

## Refactorings

- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Null Check](null-check.md) | causes |
| [Required Setup or Teardown Code](required-setup-or-teardown-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Afraid To Fail" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
