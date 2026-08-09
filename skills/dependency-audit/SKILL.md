---
name: dependency-audit
description: Run a weekly dependency audit for Composer or npm projects and propose a safe upgrade plan.
disable-model-invocation: true
---

# Dependency Audit Weekly

## Goal

Deliver a weekly dependency audit summary for the package manager this project uses.

## Detect package manager

Inspect the project root:

- `composer.json` present → **Composer** (PHP)
- `package.json` present → **npm** (JavaScript / TypeScript)
- Both present → audit **both**, report each section separately
- Neither present → stop and report that the directory is not a Composer or npm project

## Loop

Kickoff prompt (harnesses that support scheduled loops):

```text
/loop 7d Start the "Dependency Audit Weekly" loop.
Goal: deliver a weekly dependency audit summary.
Between iterations run the outdated command(s) for the detected manager(s).
Exit when: summary is posted with recommended upgrades.
```

### Composer

```bash
composer outdated --direct || true
composer audit || true
```

### npm

```bash
npm outdated || true
npm audit || true
```

Run security audit when a lockfile makes the result meaningful (`composer.lock`, `package-lock.json`, or `npm-shrinkwrap.json`).

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

- Do not modify the check command or exit criteria to force success.
- Do not skip, disable, or bypass checks to make the audit look clean.
- If package metadata is missing, dependency resolution fails, or audit output is blocked by registry/authentication issues, stop and report the blocker.
