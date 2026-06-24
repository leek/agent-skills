---
name: weekly-composer-dependency-audit
description: Run a weekly Composer dependency audit for PHP projects. Use this when the user asks for a Composer dependency audit, PHP dependency review, composer outdated package summary, composer audit, Laravel package upgrade plan, or a safe PHP dependency upgrade summary.
---

# Composer Dependency Audit Weekly

Use this skill as the Composer/PHP clone of the npm Dependency Audit Weekly loop from loops.elorm.xyz.

Source loop adapted from: https://loops.elorm.xyz/loops/dependency-audit-weekly

## Goal

Deliver a weekly Composer dependency audit summary.

## Loop

Kickoff prompt:

```text
/loop 7d Start the "Composer Dependency Audit Weekly" loop.
Goal: deliver a weekly Composer dependency audit summary.
Between iterations run: composer outdated --direct || true
Exit when: summary is posted with recommended upgrades.

Step 1: Run composer outdated and composer audit, categorize updates, and propose a safe upgrade plan.
```

Run this in the target project:

```bash
composer outdated --direct || true
```

Also run the Composer security audit:

```bash
composer audit || true
```

If there is no `composer.json`, stop and report that the current directory is not a Composer/PHP project.

## Report

Summarize the result with:

- Current package manager evidence, such as `composer.json`, `composer.lock`, and framework hints like Laravel packages.
- Outdated direct dependencies grouped by patch, minor, and major updates.
- Security advisories from `composer audit`, grouped by severity, if audit output is available.
- Recommended safe upgrade order, starting with low-risk patch and minor updates.
- Breaking-change risks, required code changes, PHP version constraints, or framework compatibility concerns for major updates.
- Exact verification commands the project should run after upgrades.

Keep the report direct. Do not apply upgrades unless the user asks you to do the upgrade work.

## Guardrails

- Do not modify the check command or exit criteria to force success.
- Do not skip, disable, or bypass checks to make the audit look clean.
- If package metadata is missing, dependency resolution fails, or audit output is blocked by registry/authentication issues, stop and report the blocker.
