---
name: blog-writing
description: Write, review, or improve a blog post against this repo's own blog style guide (voice, banned language, post types) and a shared set of craft rules. Use when drafting or reviewing a blog post, announcement, or engineering write-up, or when the user states a blog-writing preference to record as a style rule.
argument-hint: "A topic to write about, or a draft path to review"
---

# Blog Writing

Two layers of rules decide what a good post is:

- The **style guide** holds this repo's own decisions: reader, voice, banned language, formatting, post types, closing, and non-negotiables. It lives in the target repo at `.agents/blog-style.md`, and the user owns it.
- The **craft rules** below hold for any blog.

Where the two disagree, the style guide wins.

## Load the style guide

Read `.agents/blog-style.md` before you write or review. A section the guide leaves out means only the craft rules apply there.

If the file does not exist, this repo has not set the skill up. Ask the user before any other work (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat):

- **Set it up now** (recommended): bootstrap the guide per [STYLE-GUIDE-FORMAT.md](STYLE-GUIDE-FORMAT.md), then continue the task.
- **Skip this time**: continue with the craft rules alone, and say in your report that the repo has no style guide yet.

Done when you can name the reader and the voice in one line each, or the user chose to skip.

## Write

1. **Pick the post.** Choose the post type from the style guide, and state in one sentence what the reader can do or decide after reading. If you cannot, the material is too thin for a post: tell the user what is missing and stop.
2. **Gather the facts.** Collect the numbers, code, rejected alternatives, and limitations from the repo, the conversation, and the sources the user gave. A fact you cannot source is a question for the user: it goes in the draft as `TODO(author): <what is needed>`, never as an invented number, quote, or benchmark. Done when every claim the post will make has a source or a TODO.
3. **Draft.** Apply every craft rule and every style-guide rule. Save the draft where the guide's `posts:` glob puts posts, with the frontmatter those posts use. With no `posts:` glob, save to `.scratch/blog/<slug>.md`.
4. **Review your own draft** per [Review](#review) and fix what it finds.
5. **Report** the draft path, the title, each open `TODO(author)`, and any code sample you did not run.

## Review

Check the draft twice:

- **Technical pass.** Check each claim against the code or its source: numbers, benchmarks, architecture descriptions. Run each code sample, or name it as not run. Flag a simplification an expert would call wrong.
- **Editorial pass.** Check every craft rule and every style-guide rule.

Report one finding per weak passage: quote it, name the rule it breaks, and give the rewrite. A rule the draft meets stays silent. Done when every rule in both layers was checked against the whole draft, title and closing included.

## Record a rule

When the user states a blog-writing preference, corrects a draft's voice, or bans a phrase:

1. Look in `.agents/blog-style.md` for a rule that already covers it, and sharpen that rule rather than adding a near-duplicate.
2. Otherwise add it under the section it fits, in the shape that section uses in [STYLE-GUIDE-FORMAT.md](STYLE-GUIDE-FORMAT.md). A preference that would hold for any blog still goes in this repo's guide: the craft rules change only in this skill's own repo.
3. Show the user the added or changed text in your reply.

## Craft rules

### Opening

The first two or three sentences state the problem or state the conclusion. Background, company history, and announcements of what the post will cover come later or not at all.

- **Before:** "We are always looking for ways to improve the experience. Today we want to share some updates to our import tool."
- **After:** "Importing a 2 GB CSV used to take 40 minutes and fail one time in five. We rebuilt the importer around streaming, and the same file now loads in 3 minutes."

### Structure follows the reader's questions

Order the post by what the reader is wondering:

1. What problem does this solve? (one or two paragraphs)
2. How does it work underneath? (most of the post)
3. What were the trade-offs and the alternatives you rejected?
4. How do I use it or try it?

A post about engineering work also answers: what did you try that failed, and what are the known limits?

### Title

The title makes a specific claim, tells a story, or promises a specific payoff. "How we cut deploy time from 22 minutes to 4" does; "Deployment improvements" does not.

### Headings carry information

A reader who reads only the headings learns the argument. "Why pre-aggregation loses the detail you debug with" does this; "Background", "Architecture", and "Conclusion" do not.

### Paragraphs

One idea per paragraph. Start a new paragraph where the text turns ("but", "however", a change of subject), so the turn sits at the start of a block where a skimming reader sees it. A one-sentence paragraph is fine for emphasis.

### Evidence

- **Numbers over adjectives.** A performance claim carries its number: "p99 fell from 340 ms to 45 ms", in place of "significantly faster".
- **Code works.** A sample includes its imports and configuration, and its comments say why, since the code already says what.
- **Diagram a system.** More than two interacting components get a diagram, labelled with the real component names.
- **Honest claims.** State limits and beta status. Describe what a feature does with the verb that is true: "suggests a likely cause" and "finds the cause" are different claims.
- **Decisions show the alternative.** A decision is explained with what was not chosen and why.

### Written by a person

Keep the author's voice through the whole post, with first-person asides in the middle ("this is the part that tripped me up") as well as at the start and end. Rewrite these machine-prose patterns as plain connected sentences:

| Pattern | Example to rewrite | Rewrite |
|---|---|---|
| Dramatic fragments | "No errors. No warnings. Everything green." | "There were no errors or warnings, and everything looked fine." |
| Aphorism | "You can't fix what you can't see." | "Without the full request path, you are guessing." |
| Three-beat reveal | "Not a config issue. Not a code bug. The deploy was stale." | "It was not a config issue or a code bug. The deploy was stale." |
| Smug simplicity | A code block, then "That's it. That's all you need." | Say what the code does, or move on. |
| Ad-copy parallelism | "Metrics tell you what broke. Traces tell you why." | "Metrics show what broke, but you will find the reason in the traces." |

### Closing

End on something the reader can use: the docs, the source, a way to try it, or a request for feedback. Tie it to the problem the post opened with. A recap of the post or a line of hype is not a closing.

### Worth sharing

A post earns publishing when it holds at least one of: a technical decision with its trade-offs, original data, a debugging story with specifics, an honest account of a failure, or a how-to that saves the reader real time. A post with none of these needs more depth, or belongs in the changelog. When unsure about length, go deeper: thin is the more common failure than long.
