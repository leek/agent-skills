# Plan format

```markdown
# Upgrade: <package> <from> → <to>[, <package> <from> → <to> …]

<YYYY-MM-DD> · <n> releases crossed · <n> items read · <n> must · <n> should · <n> later · <n> touch nothing here

## Run set
| Package | Installed | Target | Why it is in the run |
|---|---|---|---|
| laravel/framework | 12.51.0 | 13.35.0 | requested |
| spatie/laravel-tags | 4.11.0 | 4.12.0 | its constraint excludes laravel/framework 13 |

Blockers: <package> allows at most <version> of <package>; highest reachable target <version>. Or "none".

## Must do
### 1. <title> (<package> <version>, <kind>, size S|M|L)
- **Where:** `app/Foo.php:42`, `config/bar.php:7`
- **What changes:** 1–2 lines.
- **Do:** the concrete edit or command.
- **Source:** <URL>

## Should do
<same shape; a `retires` item says which patch, pin, override, or comment goes and what replaces it>

## Do later
<same shape; an `adopt` item says what gets simpler or better and why it can wait>

## Upgrade order
1. Raise the runtime: <only if a requirement item exists>.
2. Must do items that work on both versions, landed before the bump.
3. The bump: <exact require/install command for every package in the run, one line>.
4. Must do items that need the new version, then run the test suite.
5. Should do, then Do later, each as its own change.

## Upgrade checklist
<only the lines that apply, each with its exact command or file>
- [ ] Runtime: CI matrix, Dockerfile, `.nvmrc` / `.tool-versions`, `config.platform.php`, hosting.
- [ ] Codemods: Rector set, Laravel Shift, or the package's own migration command.
- [ ] Published files: config, stubs, migrations, assets, and translations, compared with the package's new copies.
- [ ] Typings and plugins that move with the package (`@types/*`, IDE helpers, static-analysis extensions).
- [ ] Static analysis: re-run it and prune baseline entries that upstream fixed.
- [ ] Deprecation output on in tests, so the next major's work shows up now.
- [ ] Caches to clear after deploy (config, route, view, the build output).
- [ ] Deploy order, and the rollback path if the new version misbehaves.

## Sources
- <every URL read, grouped by package>
```

With an empty bucket, write `Nothing.` under its heading.
