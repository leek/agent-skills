# Oddball Solution

`Between · Bloaters · Duplication`

One problem solved two different ways in two parts of the same project. It is
duplication, but not the copy-paste kind: the shapes differ enough that no
clone detector and no diff will pair them, so you only find it by recognising
the intent. The damage is that neither variant is authoritative — a reader
cannot tell which approach is the house style, and a change to the approach
has to be applied separately to each idiosyncratic version, which is how this
smell breeds Shotgun Surgery. The usual origin is a set of near-but-not-quite
uniform interfaces that each caller adapted to in its own way.

## Detection heuristics

### Agnostic

- The same concern — retries, caching, date handling, error reporting — is
  implemented two ways, with no rule saying which is right.
- A hand-rolled implementation sitting next to a shared helper that already
  covers the case.
- The two versions differ structurally, so tooling finds nothing; only
  reading for intent surfaces the pair.
- Changing the approach means finding every bespoke variant first (see
  [Shotgun Surgery](shotgun-surgery.md)).
- New contributors ask which of the two is the pattern here, and no one can
  answer without archaeology.

### PHP / Laravel

- Outbound calls made through `Http::` in one module and a raw Guzzle client
  or cURL handle in another, with timeouts and retries configured
  independently.
- Caching via `Cache::remember()` in one service and a hand-rolled key plus
  TTL check in a sibling.
- Structurally identical work dispatched to the queue in one place and run
  inline in a controller in another.
- Dates handled with Carbon in one module and `strtotime()` / `date()` string
  juggling in the next.
- Configuration read through `config()` in one service and `env()` directly in
  another — and once `config:cache` runs, `env()` returns null outside config
  files, so the odd variant is also the broken one.

### TS / React

- Server state fetched through a query library in some components and
  hand-rolled `useEffect` plus `fetch` in others.
- Forms built with a form library on one route and controlled `useState`
  fields on the next.
- The same state machine expressed as a `useReducer` here and a cluster of
  independent booleans there.
- Failures surfaced by throwing to an error boundary on one path and returned
  as `{ error }` on another, so callers cannot handle them uniformly.
- One module parsing API responses with a schema validator while its sibling
  asserts the shape with `as` — same intent, very different guarantees.

## Example

Translated from the upstream Python example.

Smelly — each subclass builds its own connection and names the query
operation differently:

```php
abstract class Instrument
{
    // ...
}

final class Usb2Instrument extends Instrument
{
    private Socket $connection;

    public function __construct(string $ip, int $port)
    {
        $this->connection = Socket::connect("{$ip}:{$port}");
    }

    public function ask(string $command): string
    {
        return $this->connection->query($command);
    }
}

final class Usb3Instrument extends Instrument
{
    private Socket $connection;

    public function __construct(string $address)
    {
        $this->connection = Socket::connect($address);
    }

    public function read(string $command): string
    {
        return $this->connection->query($command);
    }
}
```

Solution — one adapter owns connecting and querying, and both instruments
speak through it:

```php
final class SocketAdapter
{
    private Socket $socket;

    public function __construct(string $ip, int $port)
    {
        $this->socket = Socket::connect("{$ip}:{$port}");
    }

    public function query(string $command): string
    {
        return $this->socket->query($command);
    }
}

abstract class Instrument
{
    public function __construct(protected SocketAdapter $connection)
    {
    }

    public function query(string $command): string
    {
        return $this->connection->query($command);
    }
}

final class Usb2Instrument extends Instrument
{
}

final class Usb3Instrument extends Instrument
{
}
```

## Refactorings

- Unify Interfaces with Adapter

## Related smells

| Smell | Edge |
|---|---|
| [Duplicated Code](duplicated-code.md) | co-exist |
| [Alternative Classes with Different Interfaces](alternative-classes-with-different-interfaces.md) | family |
| [Dubious Abstraction](dubious-abstraction.md) | caused |
| [Shotgun Surgery](shotgun-surgery.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Inconsistent Solution

---

*Derivative work adapted from "Oddball Solution" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
