# Triage Status Roles

The skills speak in terms of five canonical triage roles. This file maps those roles to the status strings written into markdown request files under `.scratch/`.

| Role in this skills collection | Status string in our files | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this request |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "set the AFK-ready status"), write the corresponding string as the file's status. **How** it's stored depends on the file: wayfinder-pipeline files (`map.md`, `spec.md`, `decisions/`, `issues/`) carry it in YAML frontmatter as `status:` (see `issue-tracker.md`); triage request files carry it as a `**Status:** <string>` line near the top.

Beyond these five triage roles, the pipeline adds two **build lifecycle** values, always legal on a spec or build ticket: `in-progress` (a session has claimed it) and `closed` (resolved).

Edit the right-hand column to match whatever vocabulary you actually use.
