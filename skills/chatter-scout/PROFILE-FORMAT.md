# Profile format

One profile per topic, at `docs/chatter/<topic-slug>/profile.md` in the target repo. It is the lens every sweeper and verifier receives, so write it for them: concrete names, domains, and queries beat adjectives. The user owns this file; a run never rewrites a profile that already exists.

```markdown
---
topic: <display name>
purpose: blog | digest | both        # shapes the Angle and Action fields in findings
window_days: 30                      # news older than this is stale; evergreen buckets ignore it
max_items: 10                        # kept items per findings file
covered: []                          # optional globs of already-published work, e.g. content/blog/**/*.md
---

## Lens
Who reads the output, what they do, and what makes an item matter to them (2–6 lines).
Name the load-bearing distinction a verifier must check on fetch, if there is one
(e.g. "who controls scheduling: rep or physician?").

## Buckets
- **<Bucket>**: one line on what belongs. Mark a bucket `(evergreen)` when freshness does not matter.

## Ignore
- One line per kind of item that looks relevant but is not.

## Source groups
One sweeper runs per group, in parallel, at most 5 groups a run. Merge smaller groups rather than exceed 5.

### <Group name>
- Sources: site or channel, with the URL or section to check
- Queries: `seed query one`, `seed query two`
- Notes: fetch quirks (paywall, blocks automated fetch, use search snippets only)

## Watchlist
Optional. Named players to check by name each run, grouped closest-first. When present,
it is swept as one of the source groups (it counts toward the 5).
```

## Bootstrapping a profile

When no profile exists for the topic, draft one before sweeping:

1. Run 3–5 web searches on the topic to find the trade press, regulators or standards bodies, community forums, and named players that cover it.
2. Write the profile with 3–5 source groups, each with at least two sources and two queries. `covered: []` unless the repo has an obvious published-content directory on the topic.
3. Continue the run with it, and say in the recap that the profile is a first draft to review.
