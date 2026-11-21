---
title: "What ui-design borrows from unslop-ui"
type: grilling
status: open
claimed-by:
blocked-by: []
---

## Question

Which unslop-ui (felipebasurto/unslop-ui v0.6.0) rules become ui-design house rules, and how they fit the rules already there.

## Settled

- Add all four groups: Charts, the real-state test, in-app filler, form field copy.
- Menu icons split by menu kind: action menus keep an icon on every item; place menus keep an icon only when it tells items apart (logo, avatar, file type). The Hidden states check changes to say so.

## Defaults applied

- New rules live in `skills/ui-design/SKILL.md`, not `references/` (context: docs/research/mattpocock-skills-comparison.md:42 says ui-design may be long because its body is the rules).
- Every new rule uses the house shape (rule sentence, Why, Check, generic Example, optional Except) and is written in our own words, not copied (context: Record a rule section).
- Charts becomes a new group after Data, with five rules: title names the data (a finding only when the data is fixed), no reading instructions, one encoding per value (KPI keeps figure + one direction cue + period), faint scaffolding, direct labels over a legend up to four series (established practice: Tufte / unslop U12–U16).
- Real-state test is one new rule under Data, "Status shows real state": badges, dots, and live-status strings ("Synced", "LIVE") render from a condition or value, or go; a chain of status facts keeps the one the user acts on (U6, U9, U10). Check covers code (renders from a condition) and screens (name the data that turns it off).
- In-app filler: "Every element earns its place" keeps the hero list; a new Layout rule, "No template filler", covers eyebrow labels, decorative numbering (real step order stays), and an icon in a tinted tile above each card; "Say each fact once" gains the subtitle-under-every-heading and blurb-under-every-menu-item case (default bias: sharpen existing rules over near-duplicates).
- Form field copy is a new rule under Accessibility, "One cue per field": the visible label stays; cut a placeholder that repeats it (a format example may stay) and helper text that restates it; keep constraints the user cannot guess; never replace a label with a placeholder.
- Not added: U19 heavy weights, U20 motion values (Animate disclosure already covers motion), the writing rules (brand-guidelines owns copy), the regex counter and evals (ui-design reviews, it does not bulk-edit).
- No credit line in the skill: the rules are restated in our own words.
