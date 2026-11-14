# Blog style guide format

One style guide per repo, at `.agents/blog-style.md` in the target repo. It holds the decisions that differ from one blog to the next; the craft rules in [SKILL.md](SKILL.md) hold the rest. Write each rule as a thing to do, with an example where the rule is about wording. The user owns this file: a run changes it only through **Record a rule** in SKILL.md.

```markdown
---
posts: content/blog/**/*.md      # optional glob of published posts: voice evidence, and where a new draft goes
---

# Blog style guide

## Reader
Who reads the blog, what they already know, and the bar a post must clear for them
(e.g. "a senior engineer would share it in their team chat").

## Voice
- **Sounds like:** one line, a person in a setting.
- **Does not sound like:** one line.
- **Person:** how the post names the author and the reader ("we" and "you", "I", third person).
- **Humor:** how much, and what kind.

## Banned language
- "<phrase>": what to write instead.

## Formatting
Rules past the craft rules: punctuation, paragraph length, code block and image conventions.

## Post types
| Type | Goal | Byline |
|---|---|---|
| <type> | <what the reader gets> | <who signs it> |

## Closing
What a post links to at the end, and which calls to action are allowed.

## SEO
Optional. Keyword placement, a definitional section, an FAQ, how early the product may appear.

## Non-negotiables
1. The rules that block publishing when broken.
```

Leave out a section the repo has no decision for. An empty heading reads as a rule that says nothing.

## Bootstrapping a style guide

Run this when `.agents/blog-style.md` does not exist and the user chose to set it up:

1. **Find the evidence.** Look for published posts (`content/blog/`, `posts/`, `_posts/`, a `blog` directory under the site source) and for writing guidance already in the repo (`.agents/brand-guidelines.md` from the `brand-guidelines` skill, a brand or voice doc, `CONTRIBUTING.md`, `AGENTS.md`). If the posts live outside the repo, ask the user for two or three post URLs or pasted posts.
2. **Read the three to five most recent posts** and note what they do consistently: who they address, the person they write in, their humor, how they open and close, who signs them. Set `posts:` to the glob that matches them.
3. **Interview the user**, one question per decision in the table below, in its order. Use a structured question ([harness-tools](../harness-tools/SKILL.md)), as many per call as the tool takes; otherwise ask in chat, one question at a time, with numbered options. Every option is a concrete answer the user could accept as written. The first option is your recommendation: what the posts already do, or with no posts, what fits the product and its reader. The user can always type their own answer.
4. **Confirm the draft.** Show the whole file, then ask one last structured question: write it as shown, or change a section. Repeat until the user accepts.
5. **Write the file**, say the user can edit it directly at any time, and continue the task that needed it.

| Decision | Question to ask | What the options are |
|---|---|---|
| Reader | Who is a post written for, and what bar must it clear? | Two or three reader profiles, each with its bar ("a senior engineer who would share it with their team"). |
| Voice | What should a post sound like? | Two to four voices, each a one-line "sounds like" plus the same two-sentence sample written in that voice (in the option's preview where the tool has one). |
| Person | How does a post name the author and the reader? | "We" and "you" · "I" and "you" · third person. |
| Humor | How much humor? | None · one light joke that serves the content · free, sarcasm included. |
| Banned language | Which kinds of phrase are banned? (pick several) | Groups, each listing its phrases: announcement hype ("excited to announce"), superlatives ("best-in-class"), corporate verbs ("leverage", "empower"), filler transitions ("it's worth noting"). Then ask for phrases of their own. |
| Formatting | Which formatting rules apply? (pick several) | Habits found in the posts and common house rules: no em dashes, a paragraph length limit, a language tag on every code block. |
| Post types | Which kinds of post does the blog publish? (pick several) | Engineering deep dive · product launch · postmortem · tutorial; then who signs each. |
| Byline | Who signs a post? | Always a named person · a team name is allowed. |
| Closing | What does a post end on? | The links and calls to action allowed: docs, source, a trial, a feedback request. |
| SEO | Does the blog write for search? | No section · keywords in headings only · the full set (definitional section, FAQ, product in the second half). |
| Non-negotiables | Which rules block publishing? (pick several) | The strictest rules from the answers above, as candidates. |

Skip a row only when the user already answered it in this conversation. An answer of "none" leaves that section out of the file.

Done when the file exists and every section in it is an answer the user gave or accepted.
