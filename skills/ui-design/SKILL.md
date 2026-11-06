---
name: ui-design
description: The user's UI/UX design rules, each with its reason and a check. Use when building, restyling, or reviewing a page or component, or when the user states a UI preference to record as a rule.
---

# UI Design

House rules for interfaces: what this user counts as good UI, in any stack. Each rule says what to do, why it works, how to check it on a screen, and a before → after. The list grows over time through [Record a rule](#record-a-rule).

## Build

While you build or restyle a page or component, apply every rule in [Rules](#rules) to it, including the states the default view hides ([Hidden states](#hidden-states)). Done when, for each rule, you can name how the page meets it or why the rule does not apply.

## Review

Review a page (URL), screenshots, or a UI diff against every rule. Where the harness loads this plugin's agents, dispatch and wait ([harness-tools](../harness-tools/SKILL.md)) on one sub-agent: in Claude Code, the Agent tool with `subagent_type=leek-skills:ui-reviewer`, which arrives with these rules preloaded. Brief it with what to look at (URL, screenshot paths, or the diff command), the page's purpose, and its main user. Elsewhere, review inline yourself.

Report one line per finding: `<rule> · <where> · <what is wrong> → <fix>`. A rule the page meets stays silent. Done when every rule was checked against every state the page can reach, and each state you could not reach is named.

## Record a rule

When the user states a UI preference, or shows a before and after and says why one is better:

1. Look for a rule below that already covers it. Sharpen that rule rather than adding a near-duplicate.
2. Otherwise add one under the group it fits (start a new group only when none does), in this shape:

   ```markdown
   ### <Short name>

   <The rule, as one sentence saying what to do.>

   - **Why:** <the perceptual or usability reason>
   - **Check:** <what to look for on a screen to tell it holds>
   - **Example:** <before → after, in words>
   - **Except:** <optional: when the rule yields>
   ```

3. Write the example as a generic case (a customer record, an orders table) that shows the correct pattern, in words. Leave out the app, screen, tab names, bug, or screenshot that prompted the rule: this skill is public and serves every app, and an example copied from one app teaches its quirks, not the rule.
4. Show the user the added or changed rule text in your reply.

## Rules

### Layout

#### Align and group

Give a component one alignment edge, and group its parts by role: identity, details, stats, actions.

- **Why:** the eye scans down one edge. Every extra alignment axis or mixed group is one more thing to decode. Proximity says what belongs together before anything is read.
- **Check:** count the left edges. Primary actions sit together, apart from secondary links. Repeated label and value pairs line up as columns, label small and muted above a larger value.
- **Example:** a profile card had the photo beside the name, stats as a 2×2 grid of inline "Followers 31,261" pairs, and social-icon buttons centred under the main actions. Better: a cover strip with the photo overlapping it, social links at the top right, name → bio → location on one left edge, the four stats in one row, and the two primary actions as equal full-width buttons at the bottom.

#### Nested navigation is hierarchy

Keep a second level of tabs when it is scoped to something narrower than the first (record-level tabs above, page-level tabs inside one of them), and give each level labels that do not repeat the other's.

- **Why:** nesting tells the user what each set of tabs belongs to. Flattening record and page tabs into one row loses that scope. A label shown at both levels for two different things makes the user guess which one they want.
- **Check:** each tab row belongs to one scope you can name. No label appears in both rows unless it is the same destination.
- **Example:** a customer record has record tabs (Overview, Orders, Invoices, History), and the Orders tab has its own view tabs (Open, Shipped, Returned). Two rows, two scopes, no shared labels. Merging them into one row would hide which tabs belong to the customer and which to the orders list.

#### Emphasis

Give accent colour, weight, and size to the one thing per area that needs attention; keep the rest neutral.

- **Why:** emphasis is relative. When every value is blue, nothing stands out and the user reads all of them.
- **Check:** squint at the screen; what stands out must be the most important thing there. Accent marks one state (selected, changed from the default, needs action), never a whole kind of element.
- **Example:** a settings list showed every current value as a blue chip. Better: only the value that needs attention is blue; the others are grey chips.

### Data

#### Data drives the UI

Show each value in the form its data type calls for, so the user sees the type before reading the text.

- **Why:** colour, icon, position, and weight are taken in before any reading. In a plain-text table the user must read every cell to find the one inactive row.
- **Check:** categories are tags with one consistent colour per value. Status is icon + colour + word, never colour alone. Numbers are right-aligned with tabular figures. Out-of-play rows (inactive, archived) are dimmed as a whole row. Long values truncate with an ellipsis and show in full on hover.
- **Example:** an employee table in plain text. Better: department as a tag with a coloured dot, employment as green "✓ Active" or red "✕ Inactive", years right-aligned, inactive rows greyed out, long emails truncated.

#### Fit the form to the data

Pick each visual by what the user does with the data, not by what is easiest to render.

- **Why:** a trend over time is invisible in rows, but obvious in a chart. Red pulls the eye before anything else. A face is recognised faster than a name is read.
- **Check:** change over time is a chart (with the headline total) above the detail table. Severity or priority escalates in icon and colour, with red kept for the worst level only. People show as avatar + name.
- **Example:** an incident tracker shows a bar chart of incidents per day under "214 Total", then the table: severity as bar-strength icons for Low/Medium/High and a red ⚠ for Critical, reporter as avatar + first name, category as coloured tags.

### Disclosure

#### Progressive disclosure

Show what most users need at first glance, and put the rest one interaction away, where it is used.

- **Why:** each control on screen costs attention on every visit, even for users who never use it. Depth costs one click, and only for the users who want it.
- **Check:** each level shows a summary plus the way into the next level. Nothing a user needs often is more than two levels deep.
- **Example:** the page header shows one "Share" button. It opens a popover with invite, general access, and the people list. Hovering a person there reveals the remove control.

#### Hover-reveal secondary actions

In a repeated list, show per-row actions (edit, delete, copy) when the user hovers or focuses that row.

- **Why:** N rows × 2 actions is 2N controls competing with the content. Revealing them on intent keeps the list readable and puts each action next to its target.
- **Check:** actions appear on hover and on keyboard focus (`:hover, :focus-within`). On touch, where there is no hover, they stay visible or sit in an overflow (⋯) menu. Their space is reserved, so the row does not shift. Destructive actions keep their confirm or undo.
- **Except:** a row's primary action, or one used on most visits, stays visible.
- **Example:** a notes list shows author, date, and text. "Edit" and a red "Delete" appear beside the date only while the row is hovered.

#### Spectrum of explicitness

Place each affordance on a spectrum, from labelled button to icon only, to shown on hover, to inside a menu, by how often it is used and how much it matters.

- **Why:** making everything explicit is clutter; making everything hidden is a puzzle. Frequency and importance decide the point.
- **Check:** primary and frequent actions are labelled and always visible. Occasional ones are icons with tooltips. Per-item utilities appear on hover. Rare ones sit in a menu.
- **Example:** "Add +" is a labelled black button; sort, filter, and search are icons; copy appears on a table cell only while the pointer is on it.

#### Hidden states

Design every state the default view does not show (menus, popovers, filter, sort and group builders, context menus, empty, loading and error states, onboarding, comments) with the same care as the default view.

- **Why:** most of a UI is what you cannot see in its first screenshot. A skipped state ships as an unstyled default, and users spend real time there.
- **Check:** list every state the page can reach, and look at each one. Hidden pieces use the same type scale, spacing, icon set, and radius as the default view, and menu items pair an icon with a label.
- **Example:** a database table page looks simple, but behind it sit a share popover, sort, filter, and group builders, row and column context menus, a comment thread, a getting-started checklist, and a what's-new card, all one consistent family.

### Guidance

#### Teach in place

Assume the user does not know how to use the UI, and teach at the moment and place it matters.

- **Why:** users skip manuals and tours. A hint attached to the control they are about to use gets read.
- **Check:** a key action's first use gets a dismissible hint anchored to its control, with a small visual of the result. New users get a getting-started checklist with progress. Empty states say what to do next. Each hint shows once.
- **Example:** on first visit, a dark popover points at "Add +", shows a mini row being typed, says "Add a row" with one line of description, and has a Dismiss button.

#### Tooltips on icon-only controls

Give every icon-only control a tooltip that names its action, and use the same name as its accessible label.

- **Why:** icons are ambiguous (⇅ is sort or reorder; ≡ is filter or menu). A tooltip settles it without costing space.
- **Check:** the tooltip shows on hover and on keyboard focus; `aria-label` matches it. An icon that is both ambiguous and used often gets a visible text label instead.
- **Example:** a toolbar of sort, filter, group, search, and settings icons; hovering the magnifier shows "Search".
