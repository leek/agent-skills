# Triage Status Roles

The skills speak in terms of five canonical triage roles. This file maps those roles to the `**Status:**` strings written into markdown request files under `.scratch/`.

| Role in this skills collection | Status string in our files | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this request |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "set the AFK-ready status"), use the corresponding status string from this table as `**Status:** <string>` near the top of the markdown file.

Edit the right-hand column to match whatever vocabulary you actually use.
