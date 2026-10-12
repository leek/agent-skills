# Testing rules for the target repo's AGENTS.md

Add this section once, adapted to the repo's test layers and file names. Keep the repo's own testing rules and merge in what they lack.

```markdown
## Tests

- Write the test before the code. A unit test written after the code restates it.
- Prefer integration and end-to-end tests that drive the real entry point. Have each one leave an artifact a reviewer can check and repeat (a response, persisted rows, a file).
- Before you test a part in isolation, write down the ways it can fail. Test those.
- A test that breaks under a refactor that keeps the behavior asserts the implementation. Do not add it.
- Never delete or weaken a failing test to make the suite pass. Fix the code, or ask.
```
