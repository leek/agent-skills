# Inconsistent Names

`Within · Lexical Abusers · Names`

One concept wearing a different word in every place it appears. Reading a
codebase is largely pattern matching: having learned that one class persists
through `store()`, a developer expects the sibling class doing the same job
to say `store()` too — not `add()`, `put()`, or `place()`. Each synonym
breaks that shortcut and turns a lookup into a search through variations,
and the drift compounds because the next author picks whichever word they
found first. Detect it by naming the operation out loud and collecting every
identifier in the codebase that performs it: if the collection has more than
one verb, or the antonym pairs do not pair, the vocabulary has come apart.

## Detection heuristics

### Agnostic

- Sibling types performing the same operation under synonyms — `store`,
  `save`, `persist`, `put`, `add` for one act of writing.
- Finding a behavior requires trying several synonyms before the search hits.
- Antonyms that do not match their partner: `open()` paired with
  `dispose()`, `add()` in one class against `insert()`/`delete()` in another.
- Code vocabulary drifting from the domain's own words, so one thing is a
  customer in the model, a client in the service, and an account in the API.
- Sibling classes with the same shape and no shared interface or base class
  to hold the vocabulary in place.

### PHP / Laravel

- Action and service classes exposing `handle()`, `execute()`, and `run()`
  for the same role, with no interface to pin the verb — Laravel already
  settles on `handle()` for jobs, listeners, and commands.
- Relations to the same model named differently across models: `author()` on
  one, `user()` on another, both `belongsTo(User::class)`.
- Controllers abandoning the resource verbs (`index`, `show`, `store`,
  `update`, `destroy`) for `list()`, `create()`, or `save()` in some files
  only, so route names and `Route::resource` conventions stop lining up.
- Column names drifting across migrations for one relationship —
  `created_by` on one table, `author_id` on another, `user_id` on a third.
- A Pest suite where the same behavior is described as `it('stores a
  draft')` in one file and `test('draft saving')` in the next.

### TS / React

- Data-access hooks for one resource named `useFetchUser`, `useUserQuery`,
  and `useGetUser` in three modules.
- Callback props naming the same event differently across sibling
  components — `onChange` here, `onUpdate` or `handleChange` there; React's
  convention is `onX` for the prop and `handleX` for the local handler.
- API-client functions using a different verb per resource for the same CRUD
  operation: `createUser`, `addTeam`, `newProject`.
- Types for the same shape declared as `UserDTO`, `UserModel`, and `IUser`
  in different modules, with no single exported source.
- Boolean props for the same state spelled `isDisabled`, `disabled`, and
  `inactive` across a component family.

## Example

Translated from the upstream Python example.

Smelly — two classes in the same role, one operation, two verbs; nothing in
the code forces them to agree:

```php
final class Human
{
    public function talk(string $message): void
    {
        // ...
    }
}

final class Elf
{
    public function chat(string $message): void
    {
        // ...
    }
}
```

Solution — a shared abstraction owns the word, and the compiler now enforces
what was previously a matter of habit:

```php
interface Character
{
    /** Converse with another character. */
    public function talk(string $message): void;
}

final class Human implements Character
{
    public function talk(string $message): void
    {
        // ...
    }
}

final class Elf implements Character
{
    public function talk(string $message): void
    {
        // ...
    }
}
```

## Refactorings

- Rename Method

## Related smells

| Smell | Edge |
|---|---|
| [Inconsistent Style](inconsistent-style.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Use Standard Nomenclature Where Possible

---

*Derivative work adapted from "Inconsistent Names" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
