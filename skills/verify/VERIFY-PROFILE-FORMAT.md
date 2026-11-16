# Verify profile format

One verify profile per repo, at `.agents/verify.md` in the target repo. It holds what a run needs to exercise this app and cannot find by looking: how the app is served, who to sign in as, what to watch, which data is safe to touch, and what must never fire. The user owns this file. A run changes it only through **Bootstrap** below or **Record a correction** in [SKILL.md](SKILL.md).

The file is meant to be committed, so it holds no secrets. A test login is a seeded dev account, or the seeder, command, or env var *name* that provides one. Never copy a value out of `.env`.

```markdown
# Verify

## Serve
How the app runs locally (Herd, `docker compose up`, `npm run dev`, a Procfile), the main checkout's URL, and how a worktree gets its own URL (the command that prints it, never a pinned address). Any build step the pages need (`npm run build`).

## Sign in
| Role | How |
|---|---|
| <role> | <seeded email, or the seeder / command / env var name that provides it> |

## Watch
Logs to tail and the pattern that marks an error, worker processes a flow needs (queue worker, scheduler, websocket server), and where else errors land (browser console, an error page, a debug toolbar).

## Data
The command that seeds or resets local data, the fake identity verification creates records under, records that are safe to change, and how to clean up.

## Off limits
Actions and services a run never triggers, even locally: real payments, outbound email or SMS to real addresses, third-party writes, named environments.

## Traps
Known quirks and their fix: a toolbar covering click targets, a certificate the browser must reload, a feature flag that hides the page.
```

Leave out a section the repo has no answer for.

## Bootstrap

Run this when `.agents/verify.md` does not exist and the user chose to set it up:

1. **Find the evidence.** Read `AGENTS.md` / `CLAUDE.md`, `README.md`, `composer.json` and `package.json` scripts, `.env.example`, `docker-compose.yml`, `Procfile`, the seeders and factories, and the log directory. For a Laravel app, `herd links` / `herd workspaces --json` show the served URLs. Note the stack, how it is served, the URL, seeded accounts by role, worker processes, and any service the code calls that costs money or reaches a real person.
2. **Interview the user**, one question per row below, in its order. Use a structured question ([harness-tools](../harness-tools/SKILL.md)), as many per call as the tool takes, at most 4 options each (put the rest in a follow-up question); otherwise ask in chat, one question at a time, with numbered options. Every option is a concrete answer the user could accept as written, the first one your recommendation from step 1. The user can always type their own answer.
3. **Confirm the draft.** Show the whole file, then ask one last structured question: write it as shown, or change a section. Repeat until the user accepts.
4. **Write the file** in the main checkout (the first entry of `git worktree list`), never in a worktree, where it would ride along in that branch's diff. Nothing here commits it: tell the user it is a new, uncommitted file in the main checkout, to commit on its own, and that they can edit it directly at any time. Then continue the verification that needed it.

| Decision | Question to ask | What the options are |
|---|---|---|
| Serve | How is the app served locally, and at what URL? | What step 1 found (Herd at `https://<dir>.test`, a compose port, `npm run dev`) · another way the user names. |
| Worktree URL | How does a worktree get its own URL? | The bootstrap command that prints it (`laravel-herd-worktrees`' `herd workspace`) · worktrees are not served · another way. |
| Sign in | Which account should verification sign in as, per role? (pick several) | Each seeded account step 1 found, by role · the seeder or command that creates one. |
| Watch | What should run alongside a flow? (pick several) | Tail the app log · a queue worker · the scheduler · a websocket server. Picking none leaves the section out. |
| Data | Which data may verification create or change? | Records under a fake identity the seeds already use · a fresh seed before each run · any local record. |
| Off limits | What must verification never trigger? (pick several) | Each paid or person-reaching service step 1 found (payments, email, SMS, third-party writes) · none. |
| Traps | Any known quirk a run should expect? | Quirks step 1 found · none. |

Skip a row only when the user already answered it in this conversation. An answer of "none" leaves that section out.

Done when the file exists in the main checkout and every section in it is an answer the user gave or accepted.
