# Briefs

Paste the matching section verbatim into every sweeper or verifier brief, after the run's facts (today's date, `window_days`, the profile's Lens, Buckets, and Ignore sections, and the group or batch). These rules and output shapes are the whole contract; the lead parses the JSON they return.

## Sweeper

You sweep one source group for new chatter on the topic above.

- Recall over precision: return anything plausibly on-lens; a verifier checks it later.
- Run every seed query, then up to 5 queries of your own. Fetch only listing or index pages (a news section, a press page, a subreddit listing), at most 5 fetches. Never read full articles.
- A source the notes say blocks fetch: use search snippets only, and set `"community": true` if it is a forum or social site.
- Date every item to the day: from the result, the listing page, or a date in the URL path (`/2026/08/25/`). A year or month alone is not a date, and neither is the year in a title ("… in 2026"). If no day-level date is visible, set `null`; never guess.
- Skip anything older than the window unless its bucket is marked evergreen.
- Dated, in-window items first. At most 5 undated items, and only after every dated one.
- At most 15 items. Return one JSON array and nothing else:

```json
[{"url": "…", "title": "…", "source": "publication or site", "date": "YYYY-MM-DD or null",
  "bucket": "one of the buckets", "snippet": "one line from the result", "community": false}]
```

## Verifier

You verify one batch of candidates against the lens above.

- Fetch each candidate once. Judge the page, never the headline or snippet alone.
- Confirm the publish date from the page itself. Past the window (non-evergreen bucket) is `stale`.
- Check any load-bearing distinction the lens names, and say what the page showed.
- One search is allowed per item, only to confirm a load-bearing claim from a second source.
- Candidates marked `community`, or on a site the notes say blocks fetch: do not fetch; judge from the snippet and give verdict `community`.
- Verdicts: `keep` (on-lens, dated, substantive) · `community` · `off-topic` (matches the ignore list or misses the lens) · `stale` · `thin` (no concrete facts to hang a post or digest line on) · `unreachable` (fetch failed; say how).

Return one JSON array and nothing else, one object per candidate, in batch order:

```json
[{"url": "…", "verdict": "keep", "title": "cleaned title", "source": "…", "date": "YYYY-MM-DD or null",
  "bucket": "…", "summary": "1–2 lines", "facts": ["numbers, dates, names, citations"],
  "why": "1–2 lines against the lens", "note": "reason for any verdict other than keep"}]
```
