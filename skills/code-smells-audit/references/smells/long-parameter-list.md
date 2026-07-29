# Long Parameter List

`Within · Bloaters · Measured Smells`

A signature that takes three, four, or more parameters, so every call site
becomes a riddle only the original author can read fluently. Each extra
parameter multiplies the input combinations the method must handle and the
knowledge a caller needs to use it correctly. The list usually grows in one
of two ways: a routine generalized with one more variation flag at a time, or
a method fed each field of an object individually because nobody handed it
the object — a relationship between values that exists in the domain but was
never given a type.

## Detection heuristics

### Agnostic

- Four or more parameters — or three where several always travel together
  across signatures (a [Data Clump](data-clump.md) in transit).
- Adjacent parameters of the same type: call sites can swap them and nothing
  fails until runtime.
- Boolean flags in the list (see [Flag Argument](flag-argument.md)).
- Call sites unreadable without IDE parameter hints or a comment per
  argument.
- Extending the feature means adding a parameter and touching every caller.

### PHP / Laravel

- Request fields passed individually down through controller → service →
  repository, instead of passing a FormRequest, DTO, or the model that
  already holds them.
- Methods taking five scalars that all live on one Eloquent model the caller
  already has.
- An `array $options` / `array $data` blob used to dodge the smell — the
  list is still long, now untyped and undiscoverable too.
- Call sites forced into named arguments just to stay readable — the coping
  mechanism marks the smell.
- Constructors with a long dependency list — at class scope this signals
  [Large Class](large-class.md).

### TS / React

- Functions with long positional signatures where a typed options object
  would name each value.
- Components taking a dozen props, several forwarded untouched to children
  (prop drilling) — the component-level form of the smell.
- Custom hooks taking many positional arguments instead of one params
  object.
- Boolean props and parameters multiplying rendering variants of one
  component.

## Example

Translated from the upstream Python example.

Smelly — five values that are really one concept, disassembled and
reassembled at every call:

```php
function report(string $author, string $commitId, array $files, string $shaId, string $time): void
{
    // ...
}

[$author, $commitId, $files, $shaId, $time] = getLastCommit();
report($author, $commitId, $files, $shaId, $time);
```

Solution — the values become the object they were pretending not to be, and
the behavior moves onto it:

```php
final readonly class Commit
{
    public function __construct(
        public string $author,
        public string $commitId,
        public array $files,
        public string $shaId,
        public string $time,
    ) {}

    public function report(): void
    {
        // ...
    }
}

$commit = new Commit(...getLastCommit());
$commit->report();
```

## Refactorings

- Replace Parameter with Query
- Preserve the Whole Object
- Introduce Parameter Object
- Remove Flag Argument
- Combine Functions into Class

## Related smells

| Smell | Edge |
|---|---|
| [Long Method](long-method.md) | co-exist |
| [Message Chain](message-chain.md) | co-exist |
| [Large Class](large-class.md) | causes |
| [Flag Argument](flag-argument.md) | caused |
| [Temporary Field](temporary-field.md) | caused |
| [Global Data](global-data.md) | antagonistic |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic. The antagonistic edge records a trade-off: passing
everything explicitly is the over-correction of global state, and curing one
smell can breed the other.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Long Parameter List" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
