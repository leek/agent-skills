# Testing Best Practices

A test is executable evidence of behavior, not an inventory of code. Prefer the
fewest tests that protect important decisions, invariants, contracts, and
regressions.

## Apply the value gate

Before writing or keeping a test, answer:

1. **Claim** — What behavior, business rule, regression, or contract does this
   prove?
2. **Boundary** — What public boundary can observe the claim while exercising
   the real owned code essential to it?
3. **Oracle** — What independent source supplies the expected result: a spec,
   worked example, known-good literal, or fixture not produced by the system
   under test?
4. **Sensitivity** — What realistic defect would make this test fail? Would an
   internal refactor with unchanged behavior still pass?
5. **Outcome** — What observable result proves the claim: return value,
   persisted state, emitted payload, authorization decision, or external side
   effect?

Skip a test with no meaningful claim. Rewrite or move one whose boundary,
oracle, sensitivity, or outcome is unsound. For regression coverage, witness it
fail for the expected reason before accepting the fix.

## Test behavior worth protecting

Spend tests on non-trivial branching, calculations, invariants, validation,
authorization and record scoping, state transitions, idempotency, failure and
retry behavior, integration contracts, and reproduced regressions. Include
boundary values and consequential unhappy paths, not only the happy path.

## Reject implementation coupling

- Exercise private helpers and internal state through the public interface.
- Assert outcomes rather than collaborator call order, query shape, internal
  events, or logs. Verify an interaction only when that interaction is itself
  the contract; then assert its destination, payload, count, and idempotency.
- Run owned collaborators together. Replace only external, destructive,
  expensive, or nondeterministic boundaries with faithful fakes.
- Assert functionality, never presentation: no displayed copy, labels,
  headings, navigation items, element order, CSS classes, or broad UI
  snapshots. Assert the action, validation rule, persisted data,
  authorization, or side effect behind the interface.

## Reject circular evidence

- Do not reproduce the production algorithm in the test or calculate expected
  values with the same helper, query, parser, or dependency as the code under
  test.
- Do not configure a mock to return a value and then merely assert that value
  or the call used to obtain it.
- Do not hide the assertion behind production conditionals or catch an error
  without failing the test.
- Prefer exact, behavior-specific assertions over weak signals such as “not
  null,” “did not throw,” “record exists,” or a successful status alone.

## Reject zero-value coverage

- Skip simple getters, setters, property-only constructors, passive data
  carriers, constants, enum membership, and static configuration with no
  decision or validation.
- Skip proofs that a language, library, or framework performs its own documented
  behavior, such as an ORM saving an ordinary record. Test custom wiring,
  configuration, scopes, casts, or integration behavior where it adds risk.
- Do not add tests only to execute lines or raise a coverage percentage. Treat
  uncovered risk as the target, not uncovered code.
- Avoid repeating the same claim at several layers unless each layer protects
  a distinct contract.

## Use a trustworthy boundary

- Test pure decisions and transformations as unit tests.
- Test persistence, joins, transactions, triggers, views, constraints, and
  framework wiring as integration tests against the real test schema and
  database engine—not mocked repositories or production data.
- Test external adapters against a faithful fake or provider sandbox when the
  contract matters. A unit test can cover the payload builder; it cannot prove
  that credentials, networking, or the provider work.
- Test races, locking, parallelism, async delivery, and timeout behavior with a
  coordination harness or system test that can create the real condition. A
  sequential unit test does not prove concurrency.
- Validate cloud permissions, network paths, and infrastructure rules with
  provider-native policy checks, plans, or an ephemeral/deployed environment.
  Unit-test only custom pure generation logic.

## Keep the evidence reliable

- Give each test isolated state; it must pass alone, in any order, and under
  parallel execution.
- Control clocks, randomness, identifiers, and external I/O. Never use sleeps
  or retries to conceal flakiness.
- Keep fixtures minimal and scenario-specific. Incidental fields obscure which
  inputs matter and make unrelated schema changes break tests.
- Keep one behavioral claim per test. Several assertions are appropriate when
  they jointly prove that claim.

## Review disposition

For every test under review, record one disposition:

- **Keep** — valuable claim, trustworthy boundary, independent oracle.
- **Rewrite** — valuable claim, brittle or circular proof.
- **Move** — valuable claim, wrong test level or environment.
- **Delete** — no meaningful product behavior or distinct contract.

Finish only when every new or changed test passes the value gate and every
required behavior is covered once at a trustworthy boundary.
