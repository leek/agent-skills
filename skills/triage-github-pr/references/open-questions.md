# Open questions

Read this when step 4 ends with any QUESTION, when a run stops on a hold, or when the
disposition comment already records a hold. Step numbers are the main skill's.

## Ask

When step 4 ends with any QUESTION, ping the user first (`PushNotification` where
available), because the run is often unattended. Then call the Skill tool with
`grilling` and pass every QUESTION for this PR: the finding, its link, and what each
answer would change. `grilling` asks one question at a time, frames the situation
first, and leads with a recommendation. Without the Skill tool, follow
`skills/grilling/SKILL.md` inline. Each answer turns its finding into LEGIT (fix it in
step 5) or a dismissal. The dismissal's evidence is `decided by owner: <answer>`. An
answer to hold, or a decision that belongs to someone else, is a stop case.

## A hold carries its reason

When a run stops on a hold, the disposition comment records the question, the answer,
and what is still undecided, in plain words. A later run reads that before asking
again. If it asks, the question restates what was held, why, and what would release
it; a bare "keep the hold on #N?" makes the user ask what the hold was.
