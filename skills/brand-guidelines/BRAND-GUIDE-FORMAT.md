# Brand guide format

One brand guide per repo, at `.agents/brand-guidelines.md` in the target repo. It holds the copy decisions that differ from one product to the next; the craft rules in [SKILL.md](SKILL.md) hold the rest. Write each rule as a thing to do, with an example string. The user owns this file: a run changes it only through **Record a rule** in SKILL.md.

```markdown
# Brand guidelines

## Voices

### <Name> (default)
One line on how it sounds, then any rules past the craft rules.

### <Name>
A voice with personality, if the product has one: its principles, and two or three example strings.

## Where each voice applies
| Surface | Voice |
|---|---|
| Buttons, labels, forms, settings | <default voice> |
| Empty states, 404, onboarding | <other voice> |

## Spelling and casing
The English variant (American, British), and the case for headings, buttons, and labels.

## Punctuation
Exclamation marks, periods in labels, capitals, and which dash goes where.

## Word choices
| Avoid | Prefer |
|---|---|
| "<word>" | "<word>", or what to do instead |

## Product terms
The exact spelling and capitalisation of the product, its features, and its plans, and the names users know things by.

## References
Links to the full brand or voice documentation, if any exists outside this file.
```

Leave out a section the repo has no decision for. A product with one voice has one entry under **Voices** and no **Where each voice applies** table.

## Bootstrapping a brand guide

Run this when `.agents/brand-guidelines.md` does not exist and the user chose to set it up:

1. **Find the evidence.** Look for brand or voice documentation already in the repo (a brand doc, a design-system content page, `CONTRIBUTING.md`, `AGENTS.md`), then for the copy itself: translation files (`lang/`, `locales/`, `messages/`), strings in views and components, email templates, and marketing pages. If the brand documentation lives outside the repo, ask the user for its URL or a paste.
2. **Read about 40 strings spread across surfaces** (buttons, errors, empty states, confirmations, emails, marketing) and note what they do consistently: the spelling variant, the case of headings and buttons, punctuation habits, recurring word choices, product names, and whether some surfaces carry a second voice. Where the existing copy is inconsistent, keep both forms: they become the options in step 3.
3. **Interview the user**, one question per decision in the table below, in its order. Use a structured question ([harness-tools](../harness-tools/SKILL.md)), as many per call as the tool takes; otherwise ask in chat, one question at a time, with numbered options. Every option is a concrete answer the user could accept as written. The first option is your recommendation: what the copy already does most often, or with no copy, what fits the product and its users. The user can always type their own answer.
4. **Confirm the draft.** Show the whole file, then ask one last structured question: write it as shown, or change a section. Repeat until the user accepts.
5. **Write the file**, say the user can edit it directly at any time, and continue the task that needed it.

| Decision | Question to ask | What the options are |
|---|---|---|
| Default voice | What should everyday product copy sound like? | Two to four voices, each a one-line description plus the same error message and button written in that voice (in the option's preview where the tool has one). |
| Second voice | Does any surface get more personality? | No, one voice everywhere · two to three candidate voices, each with a sample empty state and 404 line. |
| Where it applies | Which surfaces get the second voice? (pick several; only if one exists) | Empty states · 404 and error pages · onboarding · marketing and announcements. |
| Spelling | Which English? | American · British · another variant found in the copy. |
| Casing | Which case for headings, and which for buttons and labels? | Title Case headings with sentence case buttons · sentence case everywhere · Title Case everywhere. |
| Punctuation | Which punctuation rules apply? (pick several) | No exclamation marks in UI text · no period on labels and buttons · no all caps except acronyms · a dash rule. |
| Word choices | Which words does the product avoid? (pick several) | Candidates from the copy and common ones, each with its replacement: "please", "sorry", "oops", "invalid", "success!". Then ask for words of their own. |
| Product terms | Are these the right names and capitalisation? | The product, feature, and plan names found in the copy, with each inconsistent pair as a choice. |
| References | Is there brand documentation outside the repo to link? | None · the URL the user gives. |

Skip a row only when the user already answered it in this conversation. An answer of "none" leaves that section out of the file.

Done when the file exists and every section in it is an answer the user gave or accepted.
