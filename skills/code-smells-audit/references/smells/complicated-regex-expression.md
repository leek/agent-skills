# Complicated Regex Expression

`Within · Obfuscators · Names`

A regular expression dense enough that reading it means pasting it into an
online decomposer. Two distinct mistakes hide under one name. The first is
reaching for a regex at all where plain string operations would express the
same check in less time than it takes anyone to parse the pattern. The
second is writing a genuinely necessary pattern as one squeezed literal
instead of composing it from named parts — every other level of abstraction
in the codebase gets explanatory names, and the pattern should not be
exempt. A standard, widely tested pattern copied for a solved problem
(email, URL) is acceptable as-is; a bespoke one you invented for your own
format is where the smell lives, because the next reader has to debug it
character by character.

## Detection heuristics

### Agnostic

- You cannot state what the pattern matches without stepping through it
  token by token, or without a decomposer tool.
- The pattern is one literal with nested groups, alternations, and
  lookarounds and no part of it is named.
- A comment above the pattern explains what it matches — the pattern cannot
  speak for itself (see ["What" Comment](what-comment.md)).
- Regex used for work a string function does plainly: prefix and suffix
  checks, splitting on a fixed delimiter, case-insensitive equality.
- The same pattern literal duplicated across files, each copy free to be
  fixed independently.

### PHP / Laravel

- `preg_match()` / `preg_replace()` with an inline pattern literal, repeated
  in more than one class instead of living behind a named constant or a
  method that builds it from named parts.
- `regex:` or `not_regex:` rules inside a FormRequest holding a dense
  pattern, where a named Rule object — or the built-in `email`, `url`,
  `uuid`, `alpha_dash` rules — would state the intent.
- Patterns doing what `Str::startsWith()`, `Str::contains()`, `Str::before()`
  or `Str::afterLast()` do in one readable call.
- Route parameter constraints via `->where('slug', '...')` carrying a
  hand-tuned pattern with no name attached to explain the allowed shape.
- Long patterns written without the `x` modifier, when extended mode would
  let whitespace and inline comments break them across readable lines.

### TS / React

- Inline regex literals inside validation schemas (`z.string().regex(/.../)`)
  where an exported, named, unit-tested constant belongs.
- Hand-written email or URL patterns where the schema library's `.email()` /
  `.url()` already ships a tested implementation.
- Patterns assembled by string concatenation into `new RegExp()`, where every
  backslash is doubled and the result is unreviewable.
- Chained `String.prototype.replace()` calls with dense patterns doing the
  work of `split`, `trim`, or `startsWith`.
- Nested quantifiers (`(\w+\s*)+`) applied to user-supplied input —
  unreadable and a catastrophic-backtracking risk at the same time.

## Example

Translated from the upstream Python example.

Smelly — correct, probably, but nobody will verify that at review time:

```php
preg_match('/(\W|^)(\w*)\s-\s[0-9]?[0-9]:[0-9][0-9]/', $line, $matches);
```

Solution — each fragment gets the name of the thing it matches, and the
assembled pattern reads as a sentence:

```php
final class CurrentCityTimePattern
{
    /** Matches lines such as `Wroclaw - 17:42` or `San Jose - 10:42`. */
    public static function pattern(): string
    {
        $preventExcessiveMatch = '(\W|^)';
        $city = '(\w*)';
        $indication = '\s-\s';
        $hour = '[0-9]?[0-9]';
        $minute = '[0-9][0-9]';
        $time = "{$hour}:{$minute}";

        return "/{$preventExcessiveMatch}{$city}{$indication}{$time}/";
    }
}

preg_match(CurrentCityTimePattern::pattern(), $line, $matches);
```

## Refactorings

- Extract Method
- Extract Variable

## Related smells

| Smell | Edge |
|---|---|
| [Complicated Boolean Expression](complicated-boolean-expression.md) | family |
| [Clever Code](clever-code.md) | caused |
| ["What" Comment](what-comment.md) | causes |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Complicated Regex Expression" in Marcel
Jerzyk's [Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
