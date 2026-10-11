# Briefs

Paste the matching section verbatim into every worker brief, after the run's facts. These
rules and output shapes are the whole contract; the lead parses the JSON they return.

## Collector

Run facts to put above this section: the package, ecosystem, repository URL, installed
version, and this span's releases (first and last, plus the full list).

You collect every change in the releases listed above.

- Sources, in order: the official upgrade guide for any major in the span (a docs
  "Upgrade" page or `UPGRADE.md`), `CHANGELOG.md` at the last tag in the span, the
  GitHub release page for each tag (`https://api.github.com/repos/<owner>/<repo>/releases`
  pages, or `/releases/tag/<tag>`), and the security advisories for the package
  (`https://github.com/<owner>/<repo>/security/advisories`). Search only to find a source
  the repository does not link.
- One item per change. A release note that bundles several changes gives several items.
  Skip pure chores (CI, docs typos, internal test changes).
- `kind` is one of: `breaking` (removed or renamed API, changed signature, changed
  default or behaviour), `deprecation`, `security`, `fix`, `feature`, `perf`,
  `requirement` (runtime, peer, or extension version raised), `tooling` (a codemod,
  Rector set, or migration command the project can run).
- `symbols` lists every class, function, method, option, config key, CLI flag, env var,
  or event name the change names, exactly as spelled. The lead greps the codebase for
  these, so include every one and invent none.
- `refs` lists upstream issue and PR numbers or URLs the change cites. A project's
  workaround comment often links one of them.
- Fetch at most 25 pages. When the budget runs out, return what you have and list the
  releases you did not cover in `uncovered`.

Return one JSON object and nothing else:

```json
{"items": [{"version": "12.4.0", "kind": "fix", "title": "one line",
  "detail": "1-3 lines: what changed and what a user must do", "symbols": ["Str::slug"],
  "refs": ["#51234"], "source": "https://..."}],
 "sources_read": ["https://..."], "uncovered": ["12.9.0"]}
```

## Inventory

Run facts to put above this section: the package, ecosystem, installed version, and the
namespaces or import paths it ships under.

You find every place this project patches, pins, wraps, or works around the package
above. Look for, and cite each with `path:line`:

- Patch files: `extra.patches` or a patches JSON in `composer.json` (cweagans
  composer-patches), a `patches/` directory (patch-package), `pnpm.patchedDependencies`,
  a `patch:` protocol in `package.json`.
- Pins and redirects: an exact or capped version constraint, `overrides`,
  `resolutions`, a `repositories` entry pointing at a fork, `replace` or `conflict`.
- Overrides: a class that extends or replaces one of the package's classes, a container
  or service binding that swaps one, a macro, mixin, `class_alias`, prototype patch, or
  module augmentation (`declare module`), a copied-in file from the package.
- Comments near the package's code that say workaround, hack, upstream, polyfill,
  backport, "remove when", "until", TODO, or FIXME, or that link the package's issue tracker.
- Suppressions on calls into the package: `@ts-ignore`, `@ts-expect-error`,
  `@phpstan-ignore`, `@psalm-suppress`, and static-analysis baseline entries naming it.

Return one JSON array and nothing else:

```json
[{"kind": "patch | pin | override | comment | suppression", "path": "app/Foo.php",
  "line": 42, "what": "one line", "upstream_ref": "#51234 or null"}]
```

## Match

Run facts to put above this section: the package, installed and target versions, the
inventory array, and one batch of collector items (about 15).

You check each item above against this codebase. For each one, grep its `symbols` and
`refs`, read the hits, and decide:

- `hits`: the code uses what the item changes. For `breaking`, `deprecation`, and
  `requirement`, this means the upgrade breaks or warns here.
- `retires`: the item fixes or ships something an inventory entry (or other local code)
  patches, works around, or re-implements, so that local code can go. Name it.
- `adopt`: a `feature` or `perf` that would replace or simplify specific local code. Name
  the code and say what gets simpler.
- `none`: nothing in the code touches it.
- `unsure`: a hit you could not judge; say why.

Return one JSON array and nothing else, one object per item, in batch order:

```json
[{"version": "12.4.0", "title": "item title", "verdict": "hits | retires | adopt | none | unsure",
  "sites": ["app/Foo.php:42"], "note": "one line: what breaks, what goes, or what gets simpler"}]
```
