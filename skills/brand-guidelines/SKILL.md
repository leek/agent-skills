---
name: brand-guidelines
description: Write or review user-facing copy against this repo's own brand guide (voices, where each applies, spelling, word choices) and a shared set of craft rules. Use when writing UI text, error messages, empty states, onboarding, emails, or marketing copy, or when the user states a copy preference to record as a brand rule.
argument-hint: "The copy to write, or a path or diff to review"
---

# Brand Guidelines

Two layers of rules decide what good copy is:

- The **brand guide** holds this repo's own decisions: its voices, the surfaces each voice applies to, spelling, casing, punctuation, word choices, and product terms. It lives in the target repo at `.agents/brand-guidelines.md`, and the user owns it.
- The **craft rules** below hold for any product.

Where the two disagree, the brand guide wins. A blog post goes to the [blog-writing](../blog-writing/SKILL.md) skill, which has its own style guide.

## Load the brand guide

Read `.agents/brand-guidelines.md` before you write or review copy. A section the guide leaves out means only the craft rules apply there.

If the file does not exist, this repo has not set the skill up. Ask the user before any other work (a structured question ([harness-tools](../harness-tools/SKILL.md)), otherwise in chat):

- **Set it up now** (recommended): bootstrap the guide per [BRAND-GUIDE-FORMAT.md](BRAND-GUIDE-FORMAT.md), then continue the task.
- **Skip this time**: continue with the craft rules alone, and say in your reply that the repo has no brand guide yet.

Done when you can name the default voice in one line, or the user chose to skip.

## Write

1. **Name the surface** (button, form label, error, empty state, confirmation, tooltip, 404, email, marketing page) and take the voice the guide assigns to it. A surface the guide does not list gets the default voice.
2. **Use the product's existing words.** Search the existing copy and translation files for the name the product already gives the thing, and use that name. The guide's product terms win over what the code calls it.
3. **Write the copy** to every craft rule and every brand-guide rule that covers the surface.

## Review

Check each string in the page, path, or diff against both layers. Report one line per finding: `<file:line or screen> · "<current>" → "<rewrite>" · <rule>`. A string that meets the rules stays silent. Done when every user-facing string in scope was checked, including the ones the default view hides: errors, empty states, confirmations, tooltips.

## Record a rule

When the user states a copy preference, corrects a string's tone, or bans a word:

1. Look in `.agents/brand-guidelines.md` for a rule that already covers it, and sharpen that rule rather than adding a near-duplicate.
2. Otherwise add it under the section it fits, in the shape that section uses in [BRAND-GUIDE-FORMAT.md](BRAND-GUIDE-FORMAT.md). A preference that would hold for any product still goes in this repo's guide: the craft rules change only in this skill's own repo.
3. Show the user the added or changed text in your reply.

## Craft rules

### Plain by default

Copy with no voice assigned is plain: it uses the fewest words that carry the meaning, tells the user what to do, uses the active voice, and names the specific thing.

| Before | After |
|---|---|
| "Click here to save your changes" | "Save" |
| "You can filter results by date" | "Filter by date" |
| "Your changes will be saved" | "Save your changes" |
| "Some errors found" | "3 errors found" |
| "In order to continue" | "To continue" |
| "This might delete your data" (when it will) | "This deletes your data" |
| "Item has been successfully deleted" | "Deleted" |
| "Supercharge your workflow" (in the product UI) | "Speed up your workflow" |

### Personality is earned

A voice with personality goes only on the surfaces the brand guide assigns it to, where the user has a moment to spare: an empty state, a 404, onboarding. These surfaces stay plain whatever the guide assigns: error messages, destructive confirmations, billing and payment, settings, and reference documentation. There the user is frustrated, focused, or deciding whether to trust you.

- A joke aims at the situation, never at the user.
- The copy still says what happened and what to do with the joke removed.

### Buttons

A button is an action verb plus its object when the object is not obvious: "Create project", where "Create" alone leaves the user guessing. Two or three words at most, no closing punctuation.

### Error messages

Say what happened, why when that helps, and what to do next: "Could not save changes. Check your connection and try again." in place of "Error: Save failed." Name the field or value that is wrong; "Invalid input" names nothing.

### Empty states

Say what will appear here, and give the one action that fills it: "No projects yet. Create your first project to start tracking orders."

### Confirmation dialogs

The title names the action. The body states the consequence when the action destroys something. The buttons repeat the action ("Delete project", "Keep project"), so each one reads correctly alone.

### Tooltips and help text

At most two sentences. Say why the control matters, since the label already says what it is. Link to the docs for anything longer.
