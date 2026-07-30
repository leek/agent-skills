# "What" Comment

`Within · Dispensables · Names`

A comment that narrates what the code below it does, rather than why it does
it. Treating every comment as a smell is contentious, so this is the narrow
subcategory that almost always pays out: if a comment restates the mechanics
of the code, the code failed to say them itself, and the comment is
deodorant sprayed over whatever made it unreadable — an uncommunicative
name, a magic number, an unextracted phase, a bare boolean. The comment also
duplicates knowledge that now has two places to drift, so when the code moves
on and the prose does not, the smell rots into a
[Fallacious Comment](fallacious-comment.md). "Why" comments are the
opposite and are welcome: non-obvious algorithms, the reason an optimization
exists, a conclusion from a code review, domain rules a reader cannot infer.

## Detection heuristics

### Agnostic

- The comment paraphrases the statement below it. Delete it and nothing is
  lost that a better name could not carry.
- Banner comments partition a body into phases (`// validate`, `// send`) —
  each banner is an extraction whose name is already written.
- A doc block that only re-lists parameters and types the signature already
  declares.
- The comment explains an abbreviation or single-letter identifier instead of
  the identifier being renamed.
- The comment states a precondition ("must not be empty") that an assertion
  or validation rule should enforce.

### PHP / Laravel

- Docblocks repeating what PHP 8 types already say (`@param int $id`,
  `@return void`) on controllers, actions, or Eloquent models.
- Phase banners inside a controller action, queued job's `handle()`, or
  Artisan command — the banner names the action or service class that should
  exist.
- Comments annotating a magic status value (`// 2 = cancelled`) where a
  backed enum or class constant would carry the meaning
  (see [Magic Number](magic-number.md)).
- A comment beside a boolean argument explaining which behavior it selects
  (`$this->sync($order, true); // force`) — the flag needs a name, not a
  note.
- Prose describing a long query builder chain instead of a named local scope
  on the model.

### TS / React

- JSDoc mirroring the TypeScript signature (`@param {string} name`) —
  duplicated information, free to drift, checked by nothing.
- Section comments inside a component body (`// derived state`,
  `// handlers`) marking a custom hook or child component waiting to be
  extracted.
- A comment explaining what a boolean prop means at the call site rather than
  the prop being typed as a union
  (see [Boolean Blindness](boolean-blindness.md)).
- Comments narrating a dense `.filter().map().reduce()` chain instead of the
  transform being a named function.
- Comments justifying a `useEffect` dependency array instead of the effect
  being split until its dependencies are obvious.

## Example

Translated from the upstream Python example.

Smelly — two banner comments partition the method into the two methods it
should have been:

```php
public function run(): void
{
    // Creating report
    $vanillaReport = $this->reports->build($this->period);
    $tweakedReport = $this->applyAdjustments($vanillaReport);
    $finalReport = $this->formatter->format($tweakedReport);

    // Sending report
    Mail::to(config('reports.headquarters'))->queue(new ReportMail($finalReport));
    Notification::route('slack', config('reports.slack_webhook'))
        ->notify(new ReportReady($finalReport));
}
```

Solution — each banner becomes a method name, and the comments are not
deleted so much as promoted:

```php
public function run(): void
{
    $report = $this->createReport();

    $this->sendReport($report);
}

private function createReport(): Report
{
    $vanilla = $this->reports->build($this->period);

    return $this->formatter->format($this->applyAdjustments($vanilla));
}

private function sendReport(Report $report): void
{
    Mail::to(config('reports.headquarters'))->queue(new ReportMail($report));
    Notification::route('slack', config('reports.slack_webhook'))
        ->notify(new ReportReady($report));
}
```

## Refactorings

- Extract Method
- Rename Method
- Introduce Assertion

## Related smells

| Smell | Edge |
|---|---|
| [Fallacious Comment](fallacious-comment.md) | family |
| [Uncommunicative Name](uncommunicative-name.md) | caused |
| [Magic Number](magic-number.md) | caused |
| [Boolean Blindness](boolean-blindness.md) | caused |
| [Complicated Regex Expression](complicated-regex-expression.md) | caused |
| [Complicated Boolean Expression](complicated-boolean-expression.md) | caused |
| [Obscured Intent](obscured-intent.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Comment

---

*Derivative work adapted from "What" Comment in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT) — see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
