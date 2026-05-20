# DevOps Stacks Wishlist — future CRAFT extension

**Captured:** 2026-05-20 (raised during the D27 extension brainstorm).
**Status:** parked — not a D27 topic. Needs its own brainstorm thread.

## The idea

CRAFT's personality system ([D27](./brainstorm-decisions.md)) covers *development*
idioms — language, framework, test/lint/static-analysis tooling. It does not yet
cover **DevOps decisions**, which span two distinct moments:

- **Development-time** — local environment, containerization, dependency/build
  toolchain, CI configuration.
- **Deployment-time** — release strategy, target platform, infrastructure, rollout
  and rollback.

These need their own *capabilities* and *stacks* defined — analogous to D27's
Tier-2 stack-packs, but on a separate axis from development idioms.

## Open questions for the future thread

- Is "DevOps" a fourth tier, a sibling axis to D27's stack-packs, or its own pack
  family (e.g. `ops-<platform>`)?
- Where is the dev-time vs. deploy-time split drawn — one pack or two?
- How does it interact with Tier 3 (`rules.md`) — recommendation vs. project choice,
  same as the development tooling menu?

---

*No refinement in this file. A future session brainstorms these points and folds the
result into a decision.*
