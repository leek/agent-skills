# Smell baseline

A fixed set of twelve Fowler code smells (_Refactoring_, ch.3) that the Standards axis of `code-review` applies even when a repo documents nothing. Two rules bind it:

- **The repo overrides.** A documented repo standard always wins; where it endorses something the baseline would flag, suppress the smell.
- **Always a judgement call.** Each smell is a labelled heuristic ("possible Feature Envy"), never a hard violation.

The smells are defined once, in the `code-smells-audit` catalog. Each line below links its card; the one-line description of each is in that catalog's [index](../../code-smells-audit/references/index.md). Match the diff against those one-liners, and open a card (its detection heuristics, PHP/Laravel and TS/React sections, and refactorings) only for a candidate match, to confirm it and name the fix.

- [Uncommunicative Name](../../code-smells-audit/references/smells/uncommunicative-name.md)
- [Duplicated Code](../../code-smells-audit/references/smells/duplicated-code.md): within the change, the same logic shape in more than one hunk or file
- [Feature Envy](../../code-smells-audit/references/smells/feature-envy.md)
- [Data Clump](../../code-smells-audit/references/smells/data-clump.md)
- [Primitive Obsession](../../code-smells-audit/references/smells/primitive-obsession.md)
- [Conditional Complexity](../../code-smells-audit/references/smells/conditional-complexity.md): including the same `switch` or `if` cascade on one type repeated across the change (Fowler's Repeated Switches)
- [Shotgun Surgery](../../code-smells-audit/references/smells/shotgun-surgery.md): one logical change forcing scattered edits across the diff
- [Divergent Change](../../code-smells-audit/references/smells/divergent-change.md)
- [Speculative Generality](../../code-smells-audit/references/smells/speculative-generality.md): abstraction the spec has no need for
- [Message Chain](../../code-smells-audit/references/smells/message-chain.md)
- [Middle Man](../../code-smells-audit/references/smells/middle-man.md)
- [Refused Bequest](../../code-smells-audit/references/smells/refused-bequest.md)
