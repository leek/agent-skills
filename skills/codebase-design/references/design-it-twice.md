# Design It Twice

When the user wants to explore alternative interfaces for a chosen deepening candidate, use this parallel sub-agent pattern. Based on "Design It Twice" (Ousterhout): your first idea is unlikely to be the best.

Uses the vocabulary in [SKILL.md](../SKILL.md): **module**, **interface**, **seam**, **adapter**, **leverage**.

## Process

### 1. Frame the problem space

Before spawning sub-agents, write a user-facing explanation of the problem space for the chosen candidate:

- The constraints any new interface would need to satisfy
- The dependencies it would rely on, and which category they fall into (see [deepening.md](deepening.md))
- A rough illustrative code sketch to ground the constraints, not a proposal, just a way to make the constraints concrete

Show this to the user, then immediately proceed to Step 2. The user reads and thinks while the sub-agents work in parallel.

### 2. Spawn sub-agents

Spawn 3+ sub-agents in parallel, using whatever the harness provides (in Claude Code, the Agent tool; Grok, `spawn_subagent`). Each must produce a **radically different** interface for the deepened module. Where the harness has no sub-agents, produce the designs yourself one at a time, writing each down in full before starting the next; the point is genuine independence, not the parallelism.

Prompt each sub-agent with a separate technical brief (file paths, coupling details, dependency category from [deepening.md](deepening.md), what sits behind the seam). The brief is independent of the user-facing problem-space explanation in Step 1. Give each agent a different design constraint:

- Agent 1: "Minimize the interface, aim for 1–3 entry points max. Maximise leverage per entry point."
- Agent 2: "Maximise flexibility, support many use cases and extension."
- Agent 3: "Optimise for the most common caller, make the default case trivial."
- Agent 4 (if applicable): "Design around ports & adapters for cross-seam dependencies."

Include both the [SKILL.md](../SKILL.md) vocabulary and the project's `CONTEXT.md` vocabulary in the brief so each sub-agent names things consistently with the architecture language and the domain language.

Each sub-agent outputs:

1. Interface (class/method signatures with parameter and return types: plus invariants, ordering constraints, error modes)
2. Usage example showing how callers use it (controller, job, or command call site)
3. What the implementation hides behind the seam
4. Dependency strategy and adapters (see [deepening.md](deepening.md)): including container bindings if ports are involved
5. Trade-offs: where leverage is high, where it's thin

### 3. Present and compare

Present designs sequentially so the user can absorb each one, then compare them in prose. Contrast by **depth** (leverage at the interface), **locality** (where change concentrates), and **seam placement**.

After comparing, give your own recommendation: the designs as options, your pick first and marked recommended, each option's description carrying its core trade-off (`AskUserQuestion` where available, otherwise the same shape in chat). If elements from different designs would combine well, propose a hybrid as its own option. Be opinionated, the user wants a strong read, not a menu.
