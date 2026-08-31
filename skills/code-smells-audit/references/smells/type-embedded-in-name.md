# Type Embedded in Name

`Within · Couplers · Names`

A name that repeats information the declaration already carries, the type,
the container, or the class of the argument. In a language with type
declarations this is pure duplication at first, and a lie later: the type
changes, the name does not, and the name now actively misinforms. The pattern
shows up two ways. On variables and fields (`dateString`, `usersArray`) it is
a leftover habit from pointer-era languages, and a repeated prefix across them
(`playerName`, `playerHealth`) usually marks a class nobody has extracted yet.
On methods, a name that states its parameter's type (`addCourse($course)`)
outlives its accuracy the moment a supertype arrives and the method starts
accepting more than the name admits.

## Detection heuristics

### Agnostic

- A name whose suffix or prefix restates the declared type: `String`, `Int`,
  `List`, `Array`, `Obj`, `Map`.
- Several variables sharing one prefix that names a concept with no class
  behind it; the prefix is the missing type.
- A method name repeating the class of its only parameter, so the signature
  says the same thing twice.
- Generalizing the type forces a rename to keep the name honest; skipping the
  rename leaves the name stale.
- The name describes the representation rather than the meaning, which is the
  same reader problem as an [Uncommunicative Name](uncommunicative-name.md).

### PHP / Laravel

- Typed properties and promoted constructor parameters whose names repeat the
  declaration: `public string $nameString`, `public Carbon $createdAtDate`,
  `public array $optionsArray`.
- Variables suffixed with their container where the return type already says
  it, `$ordersCollection = Order::query()->get()`, `$rowsArray`.
- A repeated column prefix on one model (`customer_name`, `customer_email`,
  `customer_vat_id`) that wants to become a value object behind a custom cast
  or an `Attribute` accessor rather than five loose primitives.
- Columns whose names encode storage format instead of meaning, 
  `settings_json` cast to `array`, `expires_at_string` cast to `datetime`, 
  where the `casts` entry is the type declaration and the suffix is the copy.
- Methods named for their argument's concrete class (`notifyUser(User $user)`,
  `handleInvoicePayment(InvoicePayment $payment)`) that no longer fit once an
  interface or sibling model needs the same path.

### TS / React

- Names restating their annotation: `const dateString: string`, `userList:
  User[]`, `configObject: Config`.
- Props declaring their type twice, `itemsArray: Item[]`, `isOpenBoolean:
  boolean`: where the prop type is right beside the name.
- A cluster of same-prefixed props on one component (`playerName`,
  `playerHealth`, `playerAttack`) that should be a single `player: Player`
  prop, with the type doing the grouping.
- Fields tracking serialization state in the name (`createdAtString` living
  alongside a `createdAt: Date`), which marks parsing happening at the wrong
  boundary rather than being typed once at the edge.
- Generic parameters or helpers pinned to one concrete type in the name
  (`mapUserResponse`) that get reused for other payloads without renaming.

## Example

Translated from the upstream Python example.

Smelly: four variables sharing a prefix that names a class nobody wrote:

```php
$playerName = 'Luzkan';
$playerHealth = 100;
$playerStamina = 50;
$playerAttack = 7;
```

Solution; the prefix becomes the type, and the names drop what the
declaration now carries:

```php
final readonly class Player
{
    public function __construct(
        public string $name,
        public int $health,
        public int $stamina,
        public int $attack,
    ) {}
}

$luzkan = new Player(
    name: 'Luzkan',
    health: 100,
    stamina: 50,
    attack: 7,
);
```

The same move applies to method names: `$schedule->addCourse($course)` becomes
`$schedule->add($course)`, so the method survives the day a `Course` supertype
arrives and the schedule starts accepting more than courses.

## Refactorings

- Extract Class
- Rename Method
- Rename Variable

## Related smells

| Smell | Edge |
|---|---|
| [Primitive Obsession](primitive-obsession.md) | co-exist |
| [Uncommunicative Name](uncommunicative-name.md) | co-exist |
| [Duplicated Code](duplicated-code.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Attribute Name and Attributes Type are Opposite

---

*Derivative work adapted from "Type Embedded in Name" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
