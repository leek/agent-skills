# Maintaining the card set

Run after any card edit, batch addition, or upstream re-sync, from the skill directory:

```bash
bash scripts/validate-cards.sh            # strict: all 56 cards must exist (ship gate)
bash scripts/validate-cards.sh --partial  # mid-build: missing cards reported as pending
```

Human-readable status goes to stderr; stdout carries a JSON result:

```json
{"pass": true, "mode": "strict", "cards_present": 56, "cards_pending": 0,
 "checks": 2697, "failures": [], "pending": []}
```

Exit 0 on pass, 1 on failure (each failure names the offending file and
reason), 2 on usage errors. The script ([`../scripts/validate-cards.sh`](../scripts/validate-cards.sh)) embeds the 56-slug catalog, the closed
taxonomy vocabularies, and reads canonical refactoring names from
[refactoring-names.md](refactoring-names.md); it needs no network and no upstream clone.
