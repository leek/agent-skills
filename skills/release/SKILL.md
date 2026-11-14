---
name: release
description: "Commit this session's work, bump the version, tag, push, and publish a GitHub release with grouped notes. Use when the user asks to release, cut, tag, or publish a version."
argument-hint: "[major|minor|patch] [summary] (both inferred from the commits when omitted)"
allowed-tools: "Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git describe *) Bash(git tag --sort=*) Bash(git tag -l *) Bash(git show *) Bash(git fetch *) Bash(git rev-list *) Bash(git add *) Bash(git commit *) Bash(gh auth status) Bash(gh release view *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-plan.sh) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/release-plan.sh *) Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/bump-version.sh *)"
---

# Release

Cut one release from the current branch: every commit since the last tag, plus this
session's uncommitted work. One release, one version, one tag, one GitHub release page.

## Process

1. **Preflight.** The skill's arguments are an optional bump (`major`, `minor`, or `patch`,
   when that is the first word) and then an optional summary (the rest). Run
   `bash <this-skill-dir>/scripts/release-plan.sh [major|minor|patch]`, passing the bump
   when the user gave one (`<this-skill-dir>` is the folder this file is in). It fetches,
   changes nothing else, and prints one JSON object; this step reads `authenticated`,
   `upstream`, `behind`, and `last_tag` (null on a first release). Stop when `authenticated`
   is false, or when `behind` is above 0: a release must not race someone else's push. A null
   `upstream` means the branch tracks nothing, so `behind` is null, which is not checked:
   run `git rev-list --count HEAD..origin/<branch>` and stop when it is above 0; when
   `origin/<branch>` does not exist, the branch was never pushed and nothing is ahead of it.
   Done when you are authenticated and the branch is known not to be behind.
2. **Commit this session's work.** Only files *you* created, edited, or deleted in this
   conversation; `git status --porcelain` lines you did not touch belong to a parallel
   session and stay out. Changes under `.claude/agent-memory/` are always yours too, whoever wrote them: they are the notes of agents with `memory: project`, not a parallel session's work in progress, so they ride along in your commit (`git add -- .claude/agent-memory`). `git add -- <new-path>` each new file, then
   `git commit --only -m "<type(scope): subject>" -- <path> …` (options before the `--`).
   Never `git add -A`, `git add .`, or `commit -a`. A file that mixes your hunks with
   foreign ones is left out and named in the report. Skip this step when there is nothing
   of yours to commit. Done when `git status --porcelain` shows none of your files.
3. **Choose the version.** Run `release-plan.sh` again when step 2 committed, with the same
   bump argument as step 1, every time this step runs it. Empty
   `commits` means nothing to release. When step 2 left changes out as not this session's, ask once which
   to commit (they are often the user's own earlier work): a structured question ([harness-tools](../harness-tools/SKILL.md)),
   `multiSelect: true` with one option per file (at most 4 per question, further
   questions for the rest); otherwise list them in chat and wait. Commit the picked ones as
   step 2 does, run the plan again, and continue. Otherwise say so and stop. The version is
   `next` and `rule` is the sentence that chose it (the script's header holds the bump
   rules). Done when the new version is stated with the rule that chose it.
4. **Bump the version files.** `version_files` lists each common version file that holds
   the last version (this repo keeps it in both `.claude-plugin` files); add any other file
   the repo keeps its version in, because a file left behind stops installs from updating.
   Run `bash <this-skill-dir>/scripts/bump-version.sh <old> <new> <path> …` with both
   versions bare (no `v`). It prints `{"changed": [paths]}`, or exits 1 with nothing written
   when a file does not hold `<old>` exactly once (`matches` other than 1): bump that file
   by hand and rerun for the rest. Commit them alone, in one commit:
   `git commit --only -m "chore(release): <version>: <summary>" -- <file> …`.
   The summary is the one in the arguments when given, otherwise the headline change in six words or fewer,
   matching the style of earlier release commits. A repo with no version file is
   versioned by its tags alone, and a first release's file already holds `next`: skip the
   bump and the commit. Done when `HEAD` is the release commit or there was nothing to bump.
5. **Tag and push.** A pushed tag cannot be taken back, so first draft the step 6 notes and
   ask the user to confirm (a structured question ([harness-tools](../harness-tools/SKILL.md)): one single-select question,
   **Tag and publish** first, its `preview` showing the version, the rule that chose the
   bump, and the drafted notes; otherwise show the same in chat and wait). Act only on a
   yes. Then `git tag -a <version> -m "<version>: <summary>"`, then
   `git push origin <branch> <version>` in one command. Stop before the question when
   `tag_free` is false: the tag already exists. Done when the push reports both refs.
6. **Publish** the confirmed notes. Write the notes from the diff, not from the subjects: one bullet per
   user-visible change, grouped under `##` headings by area (the scopes in the subjects
   are a good start), the release commit itself omitted, no attribution trailers.
   `--generate-notes` alone is too thin; use it only to append the compare link.
   Save them to a file outside the repo, then
   `gh release create <version> --title "<version>: <summary>" --notes-file <file>`.
   Done when `gh release view <version>` returns a URL.
7. **Report.** The release URL, the two commit subjects with short SHAs, and any files
   deliberately left out of step 2 and why. When step 4 bumped `.claude-plugin/marketplace.json`,
   also print the command that refreshes the installed Claude Code plugin, using that file's
   `name` and the plugin `name`: `claude plugin marketplace update <marketplace>` then
   `claude plugin update <plugin>@<marketplace>`. For this repo that is
   `claude plugin marketplace update leek-agent-skills && claude plugin update leek-skills@leek-agent-skills`.
   When the repo has an executable `bin/sync-installs`, run it instead of printing that
   command, and report the before and after version it prints for each install.
   The running session keeps the previous plugin until it restarts.

## Guardrails

- Release the current branch as it stands. No branch switching, no amend, no rebase, no
  stash, no reset: a parallel session's uncommitted work is unrecoverable if discarded.
- Never force-push, and never move or delete a tag. A wrong version gets the next version.
- If the push in step 5 fails, leave the local tag in place and report the error; do not
  retry with different flags.
