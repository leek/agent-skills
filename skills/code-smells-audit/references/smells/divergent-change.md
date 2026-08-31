# Divergent Change

`Within · Change Preventers · Responsibility`

One class that changes for several unrelated reasons. A schema change edits
it, a pricing-rule change edits it, a formatting change edits it, different
motives, same file. The tell is that a small feature forces edits to methods
that have nothing to do with one another, because the class quietly
accumulated two or more kinds of decision: finding a thing and then doing
something with the thing, say, or fetching data and rendering it. It is the
inward mirror of Shotgun Surgery, there one change scatters across many
classes, here many kinds of change converge on one. The cost is a Single
Responsibility violation you feel operationally: unrelated teams keep editing
the same file, the same merge conflicts recur every sprint, and a reader has
to work out which half of the class a method belongs to before touching it.

## Detection heuristics

### Agnostic

- You can name two or more axes of change, "when the vendor API moves",
  "when the tax rules move", that both land in this one class.
- The methods fall into clusters that share no fields with each other; each
  cluster is a class waiting to be extracted.
- Git history shows commits from unrelated features touching disjoint groups
  of methods in the same file.
- You can group the methods under separate headings without renaming
  anything, which means the seam is already visible.
- The change stays inside one class; if the same feature instead scatters
  edits across many classes, it is [Shotgun Surgery](shotgun-surgery.md).

### PHP / Laravel

- An Eloquent model carrying query scopes, presentation accessors, export
  building, and notification dispatch, a schema change, a copy change, and a
  delivery change all edit the same file.
- A "manager" or service class whose top half talks to an external API and
  whose bottom half writes to the database; both vendor churn and schema churn
  hit it.
- Controller actions holding authorization and input shaping alongside report
  calculations, so a permissions change and a formula change touch the same
  method group.
- A Filament resource where the table columns, the form schema, and bespoke
  export logic each evolve on their own schedule inside one class.
- Queued jobs that both fetch remote data and render the Blade template for
  the mail they send.

### TS / React

- A component that owns data fetching, view state, and layout, so an endpoint
  change and a redesign both edit it.
- A context provider holding auth session, feature flags, and theme, three
  unrelated concerns sharing one file and one re-render.
- A hook mixing transport concerns (URL building, headers, retries) with
  domain mapping of the response.
- An `api.ts` module holding both the request plumbing and per-feature
  response shaping, so adding a feature edits the same file as changing the
  auth header.
- A reducer whose actions come from clearly separate features (`cart/*` and
  `profile/*`) handled in one `switch`.

## Example

Translated from the upstream Python example.

Smelly; one class both reads reports and modifies them, so storage changes
and editing rules land in the same file:

```php
final class ReportModifier
{
    public function getReport(string $reportName): Report
    {
        return Report::fromCsv(Storage::get($reportName));
    }

    public function modifyReport(Report $report, string $newEntry): Report
    {
        return $report->append($newEntry);
    }

    public function run(string $reportName, string $newEntry): Report
    {
        return $this->modifyReport($this->getReport($reportName), $newEntry);
    }
}

$reportModifier = new ReportModifier();
$modifiedReport = $reportModifier->run('report.csv', 'Parsed');
```

Solution: reading and modifying split into classes with one reason to change
each:

```php
final class ReportReader
{
    public function getReport(string $reportName): Report
    {
        return Report::fromCsv(Storage::get($reportName));
    }
}

final class ReportModifier
{
    public function modifyReport(Report $report, string $newEntry): Report
    {
        return $report->append($newEntry);
    }
}

$report = (new ReportReader())->getReport('report.csv');
$modifiedReport = (new ReportModifier())->modifyReport($report, 'Parsed');
```

## Refactorings

- Extract Superclass
- Extract Subclass
- Extract Class
- Extract Method
- Move Method

## Related smells

| Smell | Edge |
|---|---|
| [Shotgun Surgery](shotgun-surgery.md) | family |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

None recorded upstream.

---

*Derivative work adapted from "Divergent Change" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
