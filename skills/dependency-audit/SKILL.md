---
name: dependency-audit
description: Run a dependency audit for Composer or npm projects and propose a safe upgrade plan.
disable-model-invocation: true
context: fork
agent: leek-skills:dependency-auditor
background: false
argument-hint: "composer | npm (omit to auto-detect)"
allowed-tools: "Bash(bash *dependency-audit/scripts/audit.sh) Bash(bash *dependency-audit/scripts/audit.sh *) WebFetch"
---

# Dependency Audit

## Goal

Deliver a dependency audit summary for the package manager this project uses.

In Claude Code with this plugin installed, this skill runs in its own `dependency-auditor` subagent (read-only, remembers packages the project has chosen to hold back, in files under this repo's `.claude/agent-memory/`); the report comes back to the main session when it finishes. In other harnesses, dispatch it and wait per [harness-tools](../harness-tools/SKILL.md). Otherwise it runs inline. The steps are the same.

## Detect package manager

**The package manager is `$ARGUMENTS`.** From the project root, run `bash <this-skill-dir>/scripts/audit.sh <composer | npm>`, or with no argument when it is empty: the script then audits every manager whose manifest is there (`composer.json` → **Composer**, `package.json` → **npm**, both → **both**, each reported in its own section).

- Exit 1: the named manager's manifest is missing, or the directory is not a Composer or npm project. Stop and report that.
- Exit 2: it names any other manager. Stop and report that only Composer and npm are supported.

## Run

The script runs each manager's outdated and security-audit commands (read-only) and prints JSON, one `managers[]` entry per manager: `manifest` and `lockfile`, `outdated.patch` / `.minor` / `.major` (each entry `package`, `current`, `latest`, `direct`), `advisories` (`package`, `severity`, `id`, `title`, `url`, most severe first), and `errors`.

- `lockfile` is `null`: the security audit did not run, because only a lockfile (`composer.lock`, `package-lock.json`, or `npm-shrinkwrap.json`) makes its result meaningful. Say so in the report.
- `errors` is not empty: each line names a command that returned no result, a package the script could not compare, or an abandoned Composer package (with its replacement when Composer names one). The first kind is the blocker in **Guardrails**; carry the second into the report.
- The grouping is numeric. Whether a 0.x minor bump breaks like a major is yours to judge.

### Major bumps

For each major update, source its breaking changes from the package, not from memory: fetch its `CHANGELOG`, `UPGRADE` guide, or GitHub release notes for the versions crossed where the harness can reach the web (`WebFetch` in Claude Code), and cite the URL; otherwise read the changelog shipped under `vendor/<package>/` or `node_modules/<package>/` and mark the risk *unverified* (it covers only the installed version).

## Report

Summarize the result with:

- Package manager evidence (`composer.json` / `composer.lock`, or `package.json` / lockfile, plus framework hints when relevant)
- Outdated **direct** dependencies grouped by patch, minor, and major updates
- Security advisories from the audit command, grouped by severity, when available
- Recommended safe upgrade order, starting with low-risk patch and minor updates
- Breaking-change risks, required code changes, runtime/framework constraints, or test coverage gaps for major updates
- Exact verification commands the project should run after upgrades

Keep the report direct. Do not apply upgrades unless the user asks you to do the upgrade work.

## Guardrails

- Do not modify the script or its check commands to force success.
- Do not skip, disable, or bypass checks to make the audit look clean.
- If package metadata is missing, dependency resolution fails, or audit output is blocked by registry/authentication issues, stop and report the blocker.
