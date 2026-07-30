# Required Setup or Teardown Code

`Between · Bloaters · Responsibility`

A class or method that cannot be used on its own terms: before you call it
you have to prepare the environment, and once you are done you have to clean
up behind it — close a handle, release a lock, reset a global someone
flipped. The work is genuinely the object's, but it was pushed out onto every
caller instead, usually because the lifecycle logic got written at the call
site first and nobody ever moved it back in. Cohesion is what breaks: the
class no longer contains everything its own use requires, so it cannot be
reused in isolation, and the ceremony is copy-pasted around every call —
where sooner or later one copy skips a step and the failure surfaces
somewhere else entirely. It is also a reliable signal that the abstraction
sits at the wrong level, making callers think in sockets and handles when
what they asked for was a behaviour.

## Detection heuristics

### Agnostic

- Documentation or a comment instructs callers what to call before and after
  ("remember to close it when you're finished").
- The same short prologue or epilogue appears around every call site (see
  [Duplicated Code](duplicated-code.md)).
- Constructing the object leaves it unusable until a second `init()`,
  `configure()`, or `connect()` call lands.
- Callers must know about a resource — socket, file handle, lock, temp
  directory — they never asked for and did not create.
- Skipping the teardown leaks or corrupts rather than failing loudly, so the
  omission is found far from where it happened.
- The class's tests are mostly setup and cleanup with a thin assertion in the
  middle.

### PHP / Laravel

- A service whose constructor cannot produce a usable object, so every caller
  writes `new Client(...)` then `$client->setToken(...)->boot()` — a container
  binding or a named constructor should hand back something ready to use.
- A class that opens a resource (`fopen`, a socket, a `Cache::lock()`) and
  leaves closing or releasing to the caller, instead of taking a callback and
  wrapping it — `Cache::lock()->block()` and `DB::transaction()` are the shape
  to copy.
- Callers required to bracket every call in `DB::beginTransaction()` /
  `commit()` / `rollBack()` because the class won't manage its own boundary.
- Code that must be sandwiched in `Model::withoutEvents()`, a `Config::set()`,
  or a facade swap and then restored afterwards, with nothing enforcing the
  restore.
- Tests needing `Storage::fake()` plus manual file cleanup because the class
  writes artifacts it never removes.

### TS / React

- A hook that returns a `subscribe`/`cleanup` pair for the caller to wire into
  `useEffect`, rather than owning the effect and its cleanup internally.
- A client that requires `await client.connect()` after construction before
  any of its methods work, and `client.close()` before the process can exit.
- Callers made responsible for the `AbortController`, `setInterval` handle, or
  event listener the module itself registered.
- A component that only functions if the caller both wraps it in a specific
  provider and seeds that provider — with no error when they forget the
  second half.
- Test files with long `beforeEach`/`afterEach` blocks restoring timers,
  `fetch`, or globals the module dirtied.

## Example

Translated from the upstream Python example.

Smelly — the radio opens a socket and then makes shutting it down the caller's
problem:

```php
final class Radio
{
    public Socket $socket;

    public function __construct(string $ip, int $port)
    {
        $this->socket = Socket::connect("{$ip}:{$port}");
    }
}

$radio = new Radio($ip, $port);

// ... doing something with the object ...

// finalizing its use, at every call site
$radio->socket->shutdown(Socket::SHUT_RDWR);
$radio->socket->close();
```

Solution — the radio owns its socket's whole lifecycle, so the call site has
nothing left to remember:

```php
final class Radio
{
    private Socket $socket;

    public function __construct(string $ip, int $port)
    {
        $this->socket = Socket::connect("{$ip}:{$port}");
    }

    public function __destruct()
    {
        $this->socket->shutdown(Socket::SHUT_RDWR);
        $this->socket->close();
    }
}

$radio = new Radio($ip, $port);

// ... doing something with the object; no manual shutdown afterwards ...
```

## Refactorings

- Replace Constructor with Factory Method
- Introduce Parameter Object

## Related smells

| Smell | Edge |
|---|---|
| [Afraid To Fail](afraid-to-fail.md) | caused |
| [Dubious Abstraction](dubious-abstraction.md) | caused |
| [Hidden Dependencies](hidden-dependencies.md) | caused |
| [Duplicated Code](duplicated-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Required Setup or Teardown Code" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
