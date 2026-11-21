---
name: ui-design
description: The user's UI/UX design rules plus this repo's own UI rules, each with its reason and a check. Use when building, restyling, or reviewing a page or component, or when the user states a UI preference to record as a rule.
---

# UI Design

Two layers of rules decide what good UI is:

- The **project rules** hold this repo's own UI decisions. They live in the target repo at `.agents/ui-design.md`, and the user owns that file.
- The **house rules** in [Rules](#rules) below hold in any app and any stack. Each rule says what to do, why it works, how to check it on a screen, and gives a before → after.

Where the two disagree, the project rule wins. Both lists grow through [Record a rule](#record-a-rule).

## Load the project rules

Before you build or review, read `.agents/ui-design.md` in the current checkout; in a worktree that has none, read the main checkout's copy (the first entry of `git worktree list`). When neither exists, the house rules apply alone. Do not ask to set the file up: the first recorded rule creates it.

## Build

While you build or restyle a page or component, apply every project rule and every rule in [Rules](#rules) to it, including the states the default view hides ([Hidden states](#hidden-states)). Done when, for each rule, you can name how the page meets it or why the rule does not apply.

A fix to a shared component, class, or style covers every page that renders it. Search for each use, fix or check each one, and name the pages you covered.

## Review

Review a page (URL), screenshots, or a UI diff against every rule. Where the harness loads this plugin's agents, dispatch and wait ([harness-tools](../harness-tools/SKILL.md)) on one sub-agent: in Claude Code, the Agent tool with `subagent_type=leek-skills:ui-reviewer`, which arrives with these rules preloaded. Brief it with what to look at (URL, screenshot paths, or the diff command), the page's purpose, its main user, and the absolute path of `.agents/ui-design.md` when that file exists. Elsewhere, review inline yourself.

Report one line per finding: `<rule> · <where> · <what is wrong> → <fix>`. A rule the page meets stays silent. Done when every rule was checked against every state the page can reach, and each state you could not reach is named.

## Record a rule

When the user states a UI preference, or shows a before and after and says why one is better:

The rule goes in the `.agents/ui-design.md` you loaded. With none, create it with a `# UI design` heading in the main checkout (the first entry of `git worktree list`), never in a worktree, where it would ride along in that branch's diff. Change the house rules below only when this repo is the one that holds this skill, never in an installed copy, because the next plugin update overwrites that copy.

1. Look for a project rule or a house rule that already covers the preference. If a project rule covers it, sharpen that project rule rather than adding a near-duplicate. If only a house rule covers it: in the repo that holds this skill, sharpen that house rule; anywhere else, add a project rule that states how this repo differs.
2. Otherwise add a new rule under the group it fits (start a new group only when none does), in this shape:

   ```markdown
   ### <Short name>

   <The rule, as one sentence saying what to do.>

   - **Why:** <the perceptual or usability reason>
   - **Check:** <what to look for on a screen to tell it holds>
   - **Example:** <before → after, in words>
   - **Except:** <optional: when the rule yields>
   ```

3. In a project rule, the example may name this app's own screens. In a house rule, write the example as a generic case (a customer record, an orders table) that shows the correct pattern, in words. Leave out the app, screen, tab names, bug, or screenshot that prompted it: house rules are public and serve every app, and an example copied from one app teaches that app's quirks, not the rule.
4. Show the user the added or changed rule text in your reply.

## Rules

### Layout

#### Align and group

Give a component one alignment edge, and group its parts by role: identity, details, stats, actions.

- **Why:** the eye scans down one edge. Every extra alignment axis or mixed group is one more thing to decode. Proximity says what belongs together before anything is read.
- **Check:** count the left edges. Primary actions sit together, apart from secondary links. Repeated label and value pairs line up as columns, label small and muted above a larger value. Related metrics share one panel split by dividers, not a row of separate cards. Filters sit above the content they filter, under the page title.
- **Example:** a profile card had the photo beside the name, stats as a 2×2 grid of inline "Followers 31,261" pairs, and social-icon buttons centred under the main actions. Better: a cover strip with the photo overlapping it, social links at the top right, name → bio → location on one left edge, the four stats in one row, and the two primary actions as equal full-width buttons at the bottom.

#### Spacing shows structure

Set spacing in a deliberate hierarchy, so that each step out (inside an item → between items → between groups → between sections → page edge) gets more space than the one before, and give containers and rows enough room that nothing touches its frame.

- **Why:** when a UI feels off and no single element is wrong, the cause is usually spacing. The eye reads distance as relationship before it reads anything. Equal gaps everywhere flatten the structure, a group gap no bigger than an item gap hides where groups break, and content pressed against a container's edge looks cramped and unfinished.
- **Check:** padding inside a card is larger than the gap between cards. The gap between sections is clearly larger than the gap between cards (about twice or more). Page padding is generous (around 40px on desktop), not the same small value used inside components. In a list or sidebar, the gap between groups is several times the gap between rows, rows are tall enough for comfortable clicking (about 32px), and the list has its own inner padding so items and highlights never touch the edge. An icon beside a label has a real gap (8–10px) and is smaller than the row. Values come from one spacing scale (4, 8, 12, 16, 24, 32, 48…), not one-off numbers.
- **Example:** a dashboard had page padding, section gaps, card gaps and card padding all near 12–20px, so the stat cards, chart and list ran together. Better: 40px page padding, 48px between sections, 12px between cards, 24px inside them, and a wider sidebar. A sidebar had 4px edge padding, icons touching their labels, 26px rows, and 2px between groups. Better: 12px padding, an 8px inset, 18px icons with a 10px gap, 32px rows, and 20px between groups.

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

#### No template filler

Cut the decoration that generated screens add by reflex: a small uppercase eyebrow label over a heading, decorative numbering (01, 02, "01 //"), and an icon in a tinted tile above each card.

- **Why:** each one repeats what the heading already says or decorates nothing, and users have learned to read them as template output. Each also adds a line above a heading, so the screen gets taller and the heading weaker.
- **Check:** no small uppercase or letter-spaced text sits above a heading, as plain text or as a pill with a dot. Numbers appear only where the order is real and the user follows it (checkout steps, an install guide). A card's icon stays only when it carries meaning the title does not; a tinted tile around a generic icon goes with the icon. Uppercase table headers and keyboard keys are not eyebrows.
- **Example:** a settings page had "ACCOUNT" above "Account", sections headed "01 // Profile", "02 // Security" and "03 // Billing", and a shield in a pale-blue rounded square above the Security card. Better: plain headings "Profile", "Security" and "Billing", and no tile.

#### Run-in titles for short blurbs

When a block is a short title plus one or two sentences (feature grids, benefit lists, setting descriptions), run the title into the paragraph as a bold first sentence ending in a full stop, with the rest in the muted body colour, instead of a heading on its own line.

- **Why:** a stacked heading and body read as two separate things and leave a ragged gap between them; a short heading line also wastes most of its width. Run in, the bold phrase still catches the scanning eye, the sentence reads as one thought, and the block is a line or more shorter, so a grid of them stays even.
- **Check:** in a grid or list of short blurbs, each title sits on the same line as its body, set in the strong text colour and a heavier weight, with a full stop, and the body follows in the muted colour at the same size. No blurb has a heading line followed by only one or two body lines.
- **Example:** a feature card had "Bring your own subscription" as a heading, then "Runs on the plan you already pay for, so you can use the models you already have." on two lines below it. Better: "**Bring your own subscription.** Runs on the plan you already pay for…" as one paragraph, the first sentence dark and bold, the rest grey.
- **Except:** a section heading that introduces several paragraphs, a list, or controls keeps its own line.

#### Icon and label buttons

In a button with an icon and a label, size the icon to the label's text, keep it close to the label, pad the icon side less than the text side, and nudge lopsided glyphs until they look centred.

- **Why:** an icon carries more visual weight than the same width of text, and its bounding box holds empty space. Equal padding and a full-size icon make the content look shifted toward the icon and loosely joined. Geometric centring of a lopsided shape (a play triangle, a chevron) looks off-centre.
- **Check:** the icon is about the label's cap height, not the line height. The icon-to-label gap is smaller than the padding at either end. Padding on the icon end is visibly smaller than on the text end (roughly 3/4 of it). Squint: the icon + label group looks centred in the button, and asymmetric glyphs (▶, →, ⌄) look centred on their own axis ([Align by visual mass](#align-by-visual-mass)).
- **Example:** "+ New project", "Export", and "Watch demo" buttons had icons as tall as the text line, a wide gap, and equal padding, so each looked heavy on the icon end. Better: icons shrunk to cap height, the gap halved, the icon-end padding cut, and the play triangle moved a pixel or two toward its point so it reads as centred. Trailing icons ("Continue →", "Sort ⌄") get the same treatment, mirrored.

#### Align by visual mass

Align icons, glyphs, and short text by where their visual mass sits, not by their bounding box. When unsure, blur the element until it is a basic shape, and align that shape.

- **Why:** a bounding box includes empty corners and thin protrusions (a plane's wings and tail, a triangle's point, a numeral's descender-free baseline), so box-centred content looks shifted. Blurring hides the detail and leaves only the mass, which is what the eye actually centres.
- **Check:** blur the element in your head or the design tool (a strong Gaussian blur) and look at the blob. Centred content has its blob centred in its frame. Content in the rounded end of a pill or a circular badge sits concentric with that curve: the blob's centre is the corner radius's centre, and the gap to the curve is even all round. Compare the blob, not the box, against neighbours that should line up.
- **Example:** a status pill showed a plane icon at its left end and "47m" at its right end, both box-aligned to the inner padding. Blurred, the plane's blob sat off-centre within the left end cap, and the text sat off the right curve. Better: each nudged until its blob is concentric with its end cap.

#### Boxed rows keep the list's lines

When one item in a list is boxed (a card, an expandable panel, a highlighted row), keep its icon and text on the same vertical lines as the plain rows around it, and inset its contents evenly from the box's corner.

- **Why:** the eye follows the column of icons and the column of text down the list. A boxed row whose icon shifts a few pixels, or whose text starts at a different gap from its icon, breaks those lines and looks like a different component dropped in. Uneven insets (8px from the top, 12px from the side) make the icon look jammed into the corner instead of placed in it.
- **Check:** draw a vertical line through the icons and another at the start of the text: the boxed row's icon and text sit on both lines, and a timeline connector passes straight through its icon. The icon's inset from the box's top and side are equal, and the icon-to-text gap matches the plain rows. A trailing control (chevron, menu) has the same inset from its corner as the leading icon has from its. The box's corners are concentric with anything rounded inside it ([Nested corners are concentric](#nested-corners-are-concentric)).
- **Example:** a pull request timeline showed plain event rows and one boxed "commented" row. Inside the box, the icon sat 8px from the top and 12px from the left, and 6px from its label instead of the list's 11px, so the icon and text both missed the list's lines. Better: the box is offset so its icon lands on the timeline axis, with 11px inset top and side, an 11px gap to the label, and the chevron inset to match.

#### Nested corners are concentric

When a rounded element sits inside another rounded element, set the inner radius to the outer radius minus the inset between them, so both curves share one centre.

- **Why:** with equal radii, the inner corner bulges toward the outer one, so the gap is thinner at the corners than along the sides. The eye reads that as pinched or misaligned without being able to say why. Concentric curves keep the gap even all round, and the two layers read as one built object.
- **Check:** for each nested rounded pair (a card in a tray, an icon tile in a button, an avatar or logo in a pill, a button inside a search field), outer radius R, inset p, and inner radius r satisfy r ≈ R − p (a square inner corner when R ≤ p). Zoom into a corner: the gap band is as wide at the curve as along the straight edges. A circle in a pill's rounded end shares that end's centre, with the same gap on every side.
- **Example:** a table card with a 10px radius sat 2px inside a tray that also had a 10px radius, so the corner gap pinched. Better: the card at 8px. A workspace switcher pill had its logo circle pushed off-centre in the left end. Better: the circle centred in the end cap with a 4px gap all round.

#### Button placement follows the container

Place a form's or dialog's buttons by what contains them. On a page form, put the primary button at the left edge under the fields. In a dialog, right-align them with the primary last. In a stepper, put Back at the left and Continue at the right. On a phone sheet, stack them full width with the primary on top.

- **Why:** each position follows where the eye already is. A page form is read down its left edge, so the button sits where reading ends. A dialog ends at its bottom-right corner, where the user expects the commit action. Splitting Back and Continue maps them to backward and forward, and keeps an accidental Back away from the thumb going forward. On a narrow screen, full-width stacked buttons are easy to hit, and the primary on top is read first.
- **Check:** a page form's submit lines up with the fields' left edge, not stretched or floated right. A dialog's buttons are grouped at the bottom right, with Cancel (secondary) before Save (primary). A multi-step flow has Back at the far left and Continue at the far right, on one row. On phone widths, a sheet's or dialog's buttons are full width and stacked, with the primary above Cancel. Every container of the same kind uses the same placement across the app.
- **Example:** a profile settings form ends with "Save changes" at its left edge under the last field. A rename dialog ends with "Cancel" and "Save" at the bottom right. A three-step onboarding card has "Back" at the left and "Continue" at the right under a progress bar. A phone confirmation sheet has a full-width "Confirm" above a full-width "Cancel".
- **Except:** a platform convention the app follows on purpose (some desktop platforms put the primary first); then use it everywhere.

### Theme

#### Dark mode is its own palette

Build dark mode as its own palette, not an inverted light mode: a dark-grey base instead of black, off-white text, raised surfaces lighter than the base, depth from borders and shadows, and muted fills for coloured elements.

- **Why:** light text on a dark background glares and smears at full contrast, and saturated colours vibrate against near-black. On a dark screen a shadow alone is barely visible, so lightness is what shows elevation. Without it, cards, popovers and the page merge into one flat black.
- **Check:** the page background is not `#000`, and body text is not pure `#fff`. Each elevation step (page → card → popover or menu) is a little lighter than the one below. A floating surface has a subtle border or highlight plus a shadow. Large coloured fills (event blocks, tags, banners) use a dark, desaturated tint of their hue with the full-strength hue kept for a thin accent (a left bar, a dot, the text). The primary button is still the most prominent element, without glowing.
- **Example:** a calendar on pure black with white text and saturated blue, green, orange and purple event blocks, and a detail popover the same black as the page. Better: a dark-grey page, a slightly lighter calendar panel and a lighter popover with a hairline border and soft shadow, off-white text, and events as dim tinted blocks with a bright left bar in each event's colour.
- **Except:** a deliberate pure-black (OLED) theme the user chose; elevation and muted fills still apply.

### Data

#### Data drives the UI

Show each value in the form its data type calls for, so the user sees the type before reading the text.

- **Why:** colour, icon, position, and weight are taken in before any reading. In a plain-text table the user must read every cell to find the one inactive row.
- **Check:** categories are tags with one consistent colour per value. Status is icon + colour + word, never colour alone. Numbers are right-aligned with tabular figures. Out-of-play rows (inactive, archived) are dimmed as a whole row. The first column is the one that identifies the row (merchant, customer, title), not the date. Long values truncate with an ellipsis and show in full on hover (where the ellipsis goes: [Truncate where values differ](#truncate-where-values-differ)).
- **Example:** an employee table in plain text. Better: department as a tag with a coloured dot, employment as green "✓ Active" or red "✕ Inactive", years right-aligned, inactive rows greyed out, long emails truncated.

#### Truncate where values differ

Truncate filenames, paths, and URLs in the middle, keeping the start and the end, not at the end.

- **Why:** related files share a prefix and differ at the end (version, suffix, extension), and a path's last segment names the thing. Cutting the end removes exactly the part that tells rows apart, so a list of "report-2026…" rows all look identical.
- **Check:** in a list of long filenames, every row stays distinguishable, and the extension is visible. Paths keep the root and the last segment ("app/…/Orders/Show.php"). URLs keep the domain and the final segment. Plain prose and titles still truncate at the end. The full value shows on hover or focus and is what gets copied.
- **Example:** an attachments list showed five rows of "brand-guidelines-202…". Better: "brand-guide…draft.pdf", "brand-guide…final.pdf", "brand-guide…final-v2.pdf", "brand-guide…print.pdf", "brand-guide…web.fig".

#### Fit the form to the data

Pick each visual by what the user does with the data, not by what is easiest to render.

- **Why:** a trend over time is invisible in rows, but obvious in a chart. Red pulls the eye before anything else. A face is recognised faster than a name is read.
- **Check:** change over time is a chart (with the headline total) above the detail table. Severity or priority escalates in icon and colour, with red kept for the worst level only. People show as avatar + name.
- **Example:** an incident tracker shows a bar chart of incidents per day under "214 Total", then the table: severity as bar-strength icons for Low/Medium/High and a red ⚠ for Critical, reporter as avatar + first name, category as coloured tags.

#### Numbers carry their comparison

Show every headline number with what it is measured against (the period, the baseline, or its spread), and colour a change by whether it is good, not by its sign.

- **Why:** "1,297" or "+20%" alone makes the user guess: compared to what, over when, and is that good? A named baseline answers that in the same glance. Green for every rise and red for every fall gets it backwards for metrics where lower is better (response time, churn, cost).
- **Check:** each stat or delta names its window and baseline ("November so far, against the same days in October"; "p95 across 2.1M requests this week"), once per group, not repeated on every tile. A delta is green when the change is good and red when it is bad: a drop in review time is green. Where the trend matters, a small sparkline or distribution sits beside the number, with the previous baseline drawn for comparison.
- **Example:** three stat cards read "Orders 1,297 · +20.1% from last month", "Avg. response 4.2h · −8%" (in red), and "Refunds 12". Better: one panel captioned "This month so far vs the same days last month", each metric with a delta chip and a sparkline, and the −8% response time in green.

#### Every option reachable

Make every valid option of a select reachable: list them all, or, when the list is capped or loaded on demand, make it searchable across the full set.

- **Why:** a select that silently stops at the first N options, with no search, hides the very option the user came for. They conclude it does not exist and give up or create a duplicate. Such a select is useless.
- **Check:** count the valid options in the data and compare with what the dropdown can reach. If the list is capped (first 50, a preloaded page), typing must search the whole set, server side when needed, not just the loaded slice. A long list (more than about 10) is searchable. A short list loads with the page and keeps its options: opening the select or moving focus away does not fetch them again. Nothing filters out valid options without saying so.
- **Example:** a "Customer" select preloads the first 50 of 2,000 customers and offers no search, so customer #51 cannot be picked. Better: a searchable select that queries all 2,000 as the user types and shows matches by name and account number.

#### Status shows real state

Show a badge, a status dot, or a live-status word ("Live", "New", "Synced", "All systems operational") only when the app tracks that state and the element turns off when the state does.

- **Why:** decoration that looks like status teaches users to ignore status. A "Live" dot that always pulses is false the first time something is down, and after that users stop reading the real badges too.
- **Check:** in code, the element renders from a condition or a value (`isLive && …`, a status field, a query result); markup that always renders with fixed text is decoration and goes. On a screen, name the data that would turn it off; when there is none, it goes. A chain of three or more status facts ("12 items · Updated 2m ago · Synced · v2.1") keeps the one fact the user acts on, and the rest move to where they are needed or go. A pulsing loading skeleton is a loading state, not a status dot.
- **Example:** a dashboard header had a pulsing green dot with "Live", a "New" badge on a feature that shipped a year ago, and "Synced · v2.4 · Updated just now" under the title. Better: the dot and "Live" removed because nothing feeds them, "New" shown only to users who have not opened the feature, and one line "Updated 2 min ago" read from the real last-sync time.

### Charts

#### Title names the data

Title a chart by what it measures ("Monthly revenue"), never by its type, and make the title the finding only when the data is fixed.

- **Why:** the reader can see it is a bar chart, so "Bar chart of…" spends the most-read line on nothing. A finding as the title tells the reader what to see, but on live data it goes stale and then says something false.
- **Check:** no title contains "bar chart", "line graph", "pie chart" or "plot of". A report or static figure may state the finding ("Revenue doubled since March"); a dashboard tile fed by live data keeps the neutral name.
- **Example:** a dashboard tile titled "Line chart showing weekly active users over time". Better: "Weekly active users". In a quarterly report, the same chart can be titled "Weekly active users up 40% since launch".

#### No reading instructions

Cut captions that explain how to read a chart ("Each bar represents one month", "Hover for details"), and fix the axis or label they were covering for.

- **Why:** a chart that needs instructions has unclear axes or labels. The caption treats the symptom and costs reading time on every view, and a touch user cannot hover anyway.
- **Check:** cover each caption and chart subtitle; when what it says is already in the title, axes or labels, it goes. When it says something they do not, move that into an axis label or the title.
- **Example:** under a monthly sign-ups chart, "Each bar represents the number of new sign-ups in a month. Hover over a bar to see the exact value." Better: no caption, a y-axis labelled "Sign-ups", and month names on the x-axis.

#### One encoding per value

Show each value one way: let the axis and gridlines carry the shape, and print a number only where the reader needs the exact figure.

- **Why:** a bar, a value printed on it, a gridline at its height and an axis tick all say the same thing, and the copies crowd out the data. Text does it too: a KPI with an arrow, a percentage, the word "up" and a sentence that restates them.
- **Check:** printed values sit on the points that matter (the latest, the maximum, the one the page is about), not on every mark; when every bar does carry its value, the axis and gridlines go. A KPI shows its change once: one delta with one direction cue (an arrow or the delta's colour), not an arrow, a percentage, the word "up" and a sentence. Its baseline follows [Numbers carry their comparison](#numbers-carry-their-comparison).
- **Example:** a revenue KPI read "$48,200 ▲ 12% up" with "Revenue grew 12% compared to last month" under it. Better: "$48,200" with a green "▲ 12%" chip, under a panel caption that names the comparison once for every tile. A bar chart printed values on all twelve bars and also had a full axis and gridlines. Better: the axis and light gridlines, with only the last month's value printed.

#### Scaffolding stays faint

Draw gridlines, axes and baselines as light hairlines, and drop frames, shadows, 3D and plot backgrounds.

- **Why:** the data is what the reader came for. Heavy scaffolding competes with it; data darkest, labels next and scaffolding faintest lets the eye find the marks first.
- **Check:** no box around the plot area, no shadow or glow on bars or lines, no 3D, no fill behind the plot. Gridlines are few, 1px and light grey, and minor ticks are gone. The chart type, the data and the series colours do not change.
- **Example:** a line chart sat in a bordered panel with dark gridlines every 10 units, minor ticks and a glow on the line. Better: no border, four pale gridlines, one baseline, and the line in its plain series colour.

#### Label series directly

Put each series' name at the end of its line or beside its bar, with its latest value where useful, instead of in a legend.

- **Why:** a legend makes the reader match colours to names, back and forth, for every series. A direct label puts the name where the eye already is, and it does not depend on telling colours apart.
- **Check:** a chart with four or fewer series has no legend when its marks have room for labels. Each label sits next to its mark, in its series' colour ("This year 1,150").
- **Example:** a two-line chart of this year against last year had a legend box at the top right. Better: "This year 1,150" at the end of one line and "Last year 870" at the end of the other, and no legend.
- **Except:** more than four series, or marks too close together to label.

### Disclosure

#### Progressive disclosure

Show what most users need at first glance, and put the rest one interaction away, where it is used.

- **Why:** each control on screen costs attention on every visit, even for users who never use it. Depth costs one click, and only for the users who want it.
- **Check:** each level shows a summary plus the way into the next level. Nothing a user needs often is more than two levels deep. A record's detail pane is closed by default and opens when a row is selected, so the list gets the full width until then.
- **Example:** the page header shows one "Share" button. It opens a popover with invite, general access, and the people list. Hovering a person there reveals the remove control.

#### Say each fact once

Put each fact on screen once, in the element that shows it best, and cut any label, subline, or intro that restates what a value, badge, or heading already says.

- **Why:** every line of helper text costs reading time, and when most of it repeats what is already visible, users stop reading helper text at all, including the line that matters. Generated UI copy is especially prone to this: it explains each row as if the rest of the screen did not exist.
- **Check:** for each subline, intro, or caption, cover it and ask what the user loses. When the answer is nothing because a badge, value, or heading already says it, delete it. A subline stays only when it adds something the row cannot show: a price or rate, a time window ("Since Nov 1"), a limit's source, a consequence. Section intros that summarise the rows below go. A heading gets a subtitle only when it states a fact the heading does not ("Analytics" needs no "Understand your data better"). A menu or card list gets a blurb under each item only when the names alone cannot tell the items apart (plan tiers, settings), and then only on the items that need it.
- **Example:** a "Plan & usage" panel showed a "Free plan" badge and "$0.00" estimated cost, yet also opened with "Free plan, courtesy of the provider: nothing is charged. Usage is still measured.", put "Courtesy of the provider" under Balance, and "Not charged: free plan" under Estimated cost. Better: drop all three. Keep "1 GB free, then $0.25 per GB-month" under Storage, "Since Nov 1" under This month, and "Custom, set by support" under Daily limit, because each adds a fact nothing else on the screen shows.

#### Hover-reveal secondary actions

In a repeated list, show per-row actions (edit, delete, copy) when the user hovers or focuses that row.

- **Why:** N rows × 2 actions is 2N controls competing with the content. Revealing them on intent keeps the list readable and puts each action next to its target.
- **Check:** actions appear on hover and on keyboard focus (`:hover, :focus-within`). On touch, where there is no hover, they stay visible or sit in an overflow (⋯) menu. Their space is reserved, so the row does not shift. Destructive actions keep their confirm or undo.
- **Except:** a row's primary action, or one used on most visits, stays visible.
- **Example:** a notes list shows author, date, and text. "Edit" and a red "Delete" appear beside the date only while the row is hovered.

#### Submenus forgive diagonal paths

Give every hover-opened submenu a safe triangle: while the pointer moves from the parent item toward the open submenu, rows it crosses on the way do not take over, and only a pause (about 300ms) or leaving that path lets hover switch rows again.

- **Why:** the shortest path from a menu item to its submenu is a diagonal that crosses the rows below or above it. With instant hover, crossing "Export" on the way to "Share"'s submenu closes Share and opens Export, so the user has to trace an L-shaped path or start over. It is one of the most common small frustrations in menus, and a safe zone removes it without making hover feel slow.
- **Check:** open a submenu, then move the pointer diagonally to its far corner (the last item) across sibling rows: the submenu stays open and the crossed rows do not highlight. Stop on a sibling row for about 300ms: it takes over as normal. Moving straight down the parent menu still switches submenus immediately. Keyboard works without it: → opens the submenu, ← returns, ↑ and ↓ move between rows. Menu libraries such as Radix (sub-menu pointer grace area) and Floating UI (`safePolygon`) provide this; check it is turned on, not reimplemented.
- **Example:** a file menu (New file, Share ›, Export ›, Duplicate, Delete) has Share's submenu open. Aiming at "Invite people", the pointer cuts across Export and Duplicate. Instant hover swaps in the Export submenu. Better: the triangle from the pointer to the submenu's near edge keeps Share open; resting on Export for a moment then opens Export.

#### Animate disclosure

Animate content that expands, collapses, opens, or closes with a short eased transition (about 200–300ms), not an instant jump, and cut it to an instant change when the user asks for reduced motion.

- **Why:** an instant jump makes the content below teleport, and the user loses their place and has to work out what changed. A brief eased transition shows where the new content came from and where the rest went.
- **Check:** expand and collapse each accordion, disclosure, or detail row: height and content ease in and out (ease-out, ~200–300ms), the content below slides rather than jumps, and nothing flickers or overshoots. Rapid repeated toggles stay smooth. With `prefers-reduced-motion: reduce`, the change is instant or a plain fade.
- **Example:** clicking a collapsed comment in an activity feed snapped its body open and shoved the next event down. Better: the body grows over 300ms with an ease-out curve and the following events slide down with it.

#### Spectrum of explicitness

Place each affordance on a spectrum, from labelled button to icon only, to shown on hover, to inside a menu, by how often it is used and how much it matters.

- **Why:** making everything explicit is clutter; making everything hidden is a puzzle. Frequency and importance decide the point.
- **Check:** primary and frequent actions are labelled and always visible. Occasional ones are icons with tooltips. Per-item utilities appear on hover. Rare ones sit in a menu.
- **Example:** "Add +" is a labelled black button; sort, filter, and search are icons; copy appears on a table cell only while the pointer is on it.

#### Hidden states

Design every state the default view does not show (menus, popovers, filter, sort and group builders, context menus, empty, loading and error states, onboarding, comments) with the same care as the default view.

- **Why:** most of a UI is what you cannot see in its first screenshot. A skipped state ships as an unstyled default, and users spend real time there.
- **Check:** list every state the page can reach, and look at each one. Hidden pieces use the same type scale, spacing, icon set, and radius as the default view. In a menu of actions (edit, copy, delete), every item pairs an icon with its label; in a menu of places (pages, records, destinations), an item has an icon only when the icon tells it apart from its neighbours (a logo, an avatar, a file type), never a generic pictograph that repeats the name. Every change that loads new data (a filter, a tab, a sort, a list or board switch) shows the loading state, and every column takes part in it.
- **Example:** a database table page looks simple, but behind it sit a share popover, sort, filter, and group builders, row and column context menus, a comment thread, a getting-started checklist, and a what's-new card, all one consistent family.

### Guidance

#### Teach in place

Assume the user does not know how to use the UI, and teach at the moment and place it matters.

- **Why:** users skip manuals and tours. A hint attached to the control they are about to use gets read.
- **Check:** a key action's first use gets a dismissible hint anchored to its control, with a small visual of the result. New users get a getting-started checklist with progress. Empty states say what to do next and let the user do it right there (an inline name field, starter templates), not only link away. Each hint shows once.
- **Example:** on first visit, a dark popover points at "Add +", shows a mini row being typed, says "Add a row" with one line of description, and has a Dismiss button.

#### Controls state their outcome

Under a setting or action, say what the current choice will actually do for this user, in concrete terms, and update it as the choice changes, instead of generic help text that restates the label.

- **Why:** "Receive emails about activity" makes the user imagine the result; "About 4 a week, only when someone needs you" tells them. Concrete consequences let them choose without trying each option, and copy that would fit any product reads as filler and gets skipped.
- **Check:** each control's help text names a result (a count, a time, who is affected, what stops happening) and changes with the selected option. A setting with more than two meaningful states is a segmented control or select, not an on/off toggle. A warning names the specific thing and its deadline ("Card ending 4242 · 6 days left") and offers the fix plus a softer option ("Remind me Friday") with undo. Cover the help text and ask if it would read the same in any other app; if so, rewrite or cut it ([Say each fact once](#say-each-fact-once)).
- **Example:** an "Email notifications" toggle read "Receive emails about mentions, comments and activity." Better: Email [Mentions · All · Off], with "About 4 a week, only when someone needs you" under Mentions, changing to "About 30 a week, bundled hourly" under All. A "Payment method expiring soon" banner became "Card ending 4242 · Team plan, $48 a month", a "6 days left" chip, and "Update card" beside "Remind me Friday".

#### Tooltips on icon-only controls

Give every icon-only control a tooltip that names its action, and use the same name as its accessible label.

- **Why:** icons are ambiguous (⇅ is sort or reorder; ≡ is filter or menu). A tooltip settles it without costing space.
- **Check:** the tooltip shows on hover and on keyboard focus; `aria-label` matches it. An icon that is both ambiguous and used often gets a visible text label instead.
- **Example:** a toolbar of sort, filter, group, search, and settings icons; hovering the magnifier shows "Search".

#### Clickable looks clickable

Show the pointer cursor on everything that responds to a click: buttons, links, clickable rows and cards, and checkbox and radio inputs with their labels.

- **Why:** the cursor change is how a user finds out, before clicking, that something will respond. A clickable label with the arrow cursor reads as plain text, so the user aims at the small box instead.
- **Check:** hover each clickable element, including labels of checkboxes and radios, and see the pointer. Disabled controls and plain text keep the default cursor.
- **Example:** a filter panel's checkbox labels toggle their box but show the arrow cursor. Better: the label and the box both show the pointer, so the whole label reads as the target.

### Accessibility

#### Custom controls behave like native ones

Give every custom interactive element (an expandable card, a clickable row, a custom toggle) a real control's semantics: a role, a name that says what it is, its state, a visible focus ring, and a layout that holds up under the user's text size, contrast, and colour settings.

- **Why:** a clickable `div` looks fine with a mouse but is invisible or nameless to keyboard and screen-reader users, and a layout tuned for one font size breaks for users who enlarge text or turn on high contrast. These users meet the hidden defects first.
- **Check:** Tab reaches the control and shows a clear focus ring (`:focus-visible`), and Enter or Space activates it. The accessibility inspector shows the right role (button, link, checkbox) and a name that reads well alone ("tobias commented 2 days ago", not "button"), plus state (`aria-expanded`, `aria-pressed`, `aria-checked`). Bump the text size to 200%: nothing clips, overlaps, or truncates what matters. In forced-colours or high-contrast mode, borders, focus, and selected state are still visible. Under a different theme or accent colour, every element follows it.
- **Example:** an expandable comment card in an activity feed was a `div` with a click handler. Better: its header is a `<button aria-expanded>` whose name is the event text, with a focus ring, and the feed still reads cleanly at larger text, in high contrast, and with a purple accent theme.

#### One cue per field

Give every form field a visible label tied to its input, and cut any placeholder or helper text that only repeats it.

- **Why:** a label, placeholder and helper text that all say "Email" make the user read one fact three times, and teach them to skip helper text, including the line that matters. A placeholder used as the label disappears when the user starts typing, so they lose track of what the field was for, and screen readers may not announce it.
- **Check:** each input has a visible `<label>` tied to it (`for` and `id`, or a wrapping label). A placeholder stays only when it shows a format the label does not ("name@company.com", "DD/MM/YYYY"). Helper text stays only for a constraint the user cannot guess ("At least 12 characters") or a consequence ("Shown on your public profile"); text that says what the field is obviously for goes.
- **Example:** a sign-up form had the label "Email", the placeholder "Enter your email", and "We'll use this email to contact you" under the field. Better: the label "Email" with the placeholder "name@company.com". The password field keeps "At least 12 characters".
- **Except:** a search field with a magnifier icon may use a placeholder instead of a visible label, with an `aria-label` that matches it.

### Marketing pages

#### Every element earns its place

Cut each hero element that exists because landing pages usually have one rather than because this product needs it, and say what the product does in concrete words.

- **Why:** generated and template pages share the same filler: a numbered mono eyebrow, one italic serif accent word in the headline, a "the all-in-one workspace … seamlessly … one beautiful place" subline, round-number stats, an "As seen in" row, a secondary "See how it works", "No credit card required", a "2.0 is here →" announcement pill, an avatar stack with "★★★★★ Loved by 10,000+ teams", and a row of feature chips ("Lightning fast", "Enterprise-grade", "AI-powered"). Visitors have learned to read these as low effort and skip past them. Each one also dilutes the one thing the page needs them to read and do.
- **Check:** for each element, name what a visitor learns or can do from it that nothing else on the page gives them; remove it when you cannot. The headline names the user's problem or outcome in their own words, not the category. The subline lists what the product handles, with no adjectives. Stats and press logos appear only when they are real and someone would check them. The nav lists only places a first-time visitor would go. The hero has one primary action, labelled with the real first step ("Install on GitHub", "Start a plan"), not "Get started free"; a secondary path, if any, is a plain text link ("Read the docs").
- **Example:** a group-travel page opened with "[01] — GROUP TRAVEL, REIMAGINED", "Plan trips *together*, without the chaos.", a feature-list subline full of adjectives, two buttons, a free-forever note, three stats, and four press logos, under a four-item nav. Better: "Get the trip out of the group chat.", "Flights, stays and who owes what, in one plan the whole group can edit.", one action, and a two-item nav (Example trips, Pricing). Likewise, a code-review tool's "Build faster. Ship smarter." over "The AI-powered platform that empowers modern teams…" became "Code review that knows your codebase." over "Reads the code around every change and only comments where something would break.", with "Install on GitHub" and a "Read the docs" link.

#### Show the real product

Lead with the actual product in use, set in a real scene, and let the primary action start the task in the hero itself, instead of an abstract illustration and a generic button.

- **Why:** an orbit of floating status cards around a glowing icon could sell any product, so it tells the visitor nothing. A real screen with believable data shows what they will get, and a real photo sets the mood without decoration. An input that begins the task ("Where are you going?") turns the click into a first step of the job, not a jump to a sign-up form.
- **Check:** the hero visual is a real screen of the product, or a faithful mock with plausible data (names, times, amounts), not icons, gradients and orbits. Photography is real and specific to the product's use. The primary action is the first step of the core task when that step is one field. Colour comes from the content (the photo, the product), so the chrome can stay neutral: a white or near-white page and a black or neutral primary button, not a brand colour on every control. No gradient or glowing backgrounds, gradient-filled headline words, or gradient buttons with an emoji.
- **Example:** a travel planner's hero showed a glowing globe icon with "Flight booked", "6 friends joined" and "€1,240 split" cards orbiting it on a cream background, with an orange "Start planning" button. Better: a full-width coastal photo with the real itinerary card on top (Lisbon, Fri 12 – Mon 15 June, six avatars, flights, stay, train, "You owe Marta €84 · Settle up"), above a "Where are you going?" field with a black "Start a plan" button, on white.
- **Except:** a product with no screen to show (an API, a service). Show its output or a real customer instead, not an abstract illustration.
