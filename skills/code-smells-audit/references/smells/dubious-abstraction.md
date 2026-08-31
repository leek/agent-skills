# Dubious Abstraction

`Within · Change Preventers · Responsibility`

A unit whose body swings between levels of abstraction, so a reader never
knows which altitude they are at. Robert Martin's rule is that a function
should descend exactly one level below the operation its name promises; when
a method named for a business step also carries the plumbing for one of those
steps, the two levels sit at the same indentation and the reader has to hold
both in mind at once. The same fault appears in names, a concept labelled
after its storage or transport representation rather than what it means.
The cost is comprehensibility and extension: a mental map of the workflow
cannot form, and a mechanism baked into the wrong layer has to be prised out
before anything can vary. It arises from tunnel vision, deciding an
abstraction is correct requires deliberately stepping outside the code you
just wrote, and consistency is a poor defence when every level is
consistently wrong.

## Detection heuristics

### Agnostic

- Within a few lines the vocabulary drops from policy ("approve", "settle")
  to mechanism ("socket", "buffer", "column") and back again.
- The method's name describes an operation, but the body both sequences that
  operation's steps *and* implements one of them.
- One public interface mixes intent-level operations with the low-level
  utilities they are built from, so callers cannot tell which is the
  supported entry point.
- A name borrowed from the wrong layer, a domain object named after its
  wire format, or an entity method named after the mechanism it uses.
- Asking "is this really this object's job?" starts an argument instead of
  producing an answer; the answer given is that it has always been this way.
- Extraction is resisted because both halves "belong to the same feature", 
  a feature is not an abstraction level (see [Long Method](long-method.md)).

### PHP / Laravel

- An action or service method that reads as a workflow yet also assembles
  raw SQL through `DB::statement()`, or hand-builds an HTTP request with
  headers and retry logic, beside its domain calls.
- Eloquent models exposing domain operations (`$order->cancel()`) alongside
  presentation or transport helpers (`toCsvRow()`, `postToWebhook()`) on the
  same class.
- A job's `handle()` that names a business step but inlines `Storage::disk()`
  path arithmetic, stream handling, or serialization instead of delegating.
- Controllers reaching through the framework's floorboards, pulling the raw
  PDO handle out of a connection, or resolving services from `app()` mid
  method: inside code otherwise written in request/response terms.

### TS / React

- A component named for a domain concept whose body also builds URLs, sets
  auth headers, and parses the response, rather than calling a typed client.
- A custom hook returning both a domain API and the raw primitive behind it
  (`{ addItem, setState }`), so callers may bypass the abstraction.
- Reducer cases that decide policy and also format dates or strings inline.
- Context providers exposing a domain interface next to the underlying
  transport object (the socket, the HTTP client) they were meant to hide.
- Helpers whose names sit a level above what they do: `formatUser()` that
  also fetches, `getTotal()` that also writes to storage.

## Example

Translated from the upstream Python example.

Smelly: `reset()` speaks the instrument's language, but `write()` is the
adapter's job and now lives on the instrument too:

```php
abstract class Instrument
{
    protected ConnectionAdapter $adapter;

    public function reset(): void
    {
        $this->write('*RST');
    }

    protected function write(string $command): void
    {
        // ...
    }
}
```

Solution: `reset()` descends exactly one level, to the adapter that owns
the wire protocol:

```php
abstract class Instrument
{
    protected ConnectionAdapter $adapter;

    public function reset(): void
    {
        $this->adapter->write('*RST');
    }
}
```

## Refactorings

- Extract Superclass
- Extract Subclass
- Extract Class

## Related smells

| Smell | Edge |
|---|---|
| [Speculative Generality](speculative-generality.md) | family, antagonistic |
| [Long Method](long-method.md) | co-exist |
| [Large Class](large-class.md) | co-exist |
| [Refused Bequest](refused-bequest.md) | co-exist |
| [Oddball Solution](oddball-solution.md) | causes |
| [Required Setup/Teardown Code](required-setup-or-teardown-code.md) | causes |
| [Side Effects](side-effects.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Inconsistent Abstraction Levels, Functions Should Descend Only One Level of
Abstraction, Code at Wrong Level of Abstraction, Choose Names at the
Appropriate Level of Abstraction

---

*Derivative work adapted from "Dubious Abstraction" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
