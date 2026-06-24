---
name: weekly-npm-dependency-audit
description: Run a weekly npm dependency audit for JavaScript or TypeScript projects. Use this when the user asks for an npm dependency audit, npm outdated package review, package.json upgrade plan, weekly dependency audit, npm security check, or a safe npm upgrade summary.
---

# NPM Dependency Audit Weekly

## Goal

Deliver a weekly npm dependency audit summary.

## Loop

Kickoff prompt:

```text
/loop 7d Start the "NPM Dependency Audit Weekly" loop.
Goal: deliver a weekly npm dependency audit summary.
Between iterations run: npm outdated || true
Exit when: summary is posted with recommended upgrades.

Step 1: Run npm outdated, categorize updates, and propose a safe upgrade plan.
```

Run this in the target project:

```bash
npm outdated || true
```

Also run a security audit when the project has a lockfile that makes the result meaningful:

```bash
npm audit || true
```

If there is no `package.json`, stop and report that the current directory is not an npm project.

## Report

Summarize the result with:

- Current package manager evidence, such as `package-lock.json`, `npm-shrinkwrap.json`, or npm scripts.
- Outdated dependencies grouped by patch, minor, and major updates.
- Security advisories from `npm audit`, grouped by severity, if audit output is available.
- Recommended safe upgrade order, starting with low-risk patch and minor updates.
- Breaking-change risks, required code changes, or test coverage gaps for major updates.
- Exact verification commands the project should run after upgrades.

Keep the report direct. Do not apply upgrades unless the user asks you to do the upgrade work.

## Guardrails

- Do not modify the check command or exit criteria to force success.
- Do not skip, disable, or bypass checks to make the audit look clean.
- If package metadata is missing, dependency resolution fails, or audit output is blocked by registry/authentication issues, stop and report the blocker.
