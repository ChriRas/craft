---
description: Update the CRAFT plugin marketplace clone from GitHub. Syncs the marketplace, shows incoming commits, requires explicit confirmation, then asks Claude Code to install the new version on next start. Pre/Post-Assertions, no silent mutations.
allowed-tools: ["Bash", "Read"]
---

# /craft:upgrade — Pull the Latest CRAFT Release

## Purpose

Bring the locally cached CRAFT marketplace clone up to date with `origin/main` on GitHub, so Claude Code can install the new plugin version on the next session start.

`/craft:upgrade` updates the **marketplace clone** (`~/.claude/plugins/marketplaces/<marketplace-name>/`). It does **not** touch the plugin cache (`~/.claude/plugins/cache/...`) or rewrite `installed_plugins.json` — those are Claude Code's responsibility. Releasing CRAFT itself (version bump, tag, push) is a manual maintainer step and is **not** automated by this command.

This command is intentionally minimal: CRAFT is pure Markdown, so there is no build, no native addons, and no MCP server to restart in-process. A session restart is sufficient for Claude Code to detect the new version and re-install from the synced marketplace.

---

## Pre-flight

### Step 1 — Locate the installed CRAFT entry

Read `~/.claude/plugins/installed_plugins.json`. Find the key matching `craft@<marketplace-name>` (e.g. `craft@craft`).

- If no such entry exists → abort:

  ```
  CRAFT is not installed via a marketplace. /craft:upgrade only works for
  marketplace-installed plugins. If you are running CRAFT directly from a
  local clone, use git pull in that clone instead.
  ```

- If multiple entries exist (e.g. user-scope + project-scope), prefer the user-scope entry; if none is user-scope, abort with a list of candidates and ask the user which to upgrade.

Extract:
- `marketplaceName` (the part after `@` in the key)
- `installedVersion` (from `version`)
- `installPath`
- `gitCommitSha` (if present)

### Step 2 — Locate the marketplace clone

Build the marketplace path: `<HOME>/.claude/plugins/marketplaces/<marketplaceName>/`.

- If the directory does not exist → abort with: *"Marketplace clone for `<marketplaceName>` not found at `<path>`. Reinstall CRAFT via Claude Code's plugin manager and re-run /craft:upgrade."*
- If `<path>/.git` is missing → abort: *"`<path>` is not a git working tree. Cannot upgrade a non-git marketplace."*

Let this directory be `<mkt>` for the rest of the procedure.

---

## Pre-Assertions

Run all four. Any failure stops the command — never silently overrides.

### A1 — Marketplace describes CRAFT

- Read `<mkt>/.claude-plugin/marketplace.json`.
- Confirm a `plugins[]` entry exists with `"name": "craft"`. If not → abort: *"Marketplace at `<mkt>` does not list a `craft` plugin. Refusing to upgrade a foreign marketplace."*

### A2 — Working tree clean

```
git -C <mkt> status --porcelain
```

If output is non-empty → abort with:

```
⚠ Marketplace clone at <mkt> has local changes:

<first 10 lines of porcelain output>

/craft:upgrade will never silently discard work. Resolve manually
(commit, stash, or git checkout -- <files>) and re-run.
```

### A3 — On the upgrade branch

```
git -C <mkt> rev-parse --abbrev-ref HEAD
```

If the branch is not `main` → abort:

```
⚠ Marketplace clone is on branch "<branch>", not "main".
   Run `git -C <mkt> checkout main` and re-run /craft:upgrade.
```

### A4 — Remote configured

```
git -C <mkt> remote get-url origin
```

If no `origin` → abort with the missing-remote message.

---

## Procedure

### 1. Fetch

```
git -C <mkt> fetch --tags origin
```

Network failure → abort with the git error verbatim and the hint *"Check connectivity and `git -C <mkt> remote -v` configuration."*

### 2. Compare SHAs and versions

```
git -C <mkt> rev-parse HEAD
git -C <mkt> rev-parse origin/main
```

If the SHAs are equal:

```
Already on latest (<installedVersion>, commit <short SHA>). Nothing to do.
```

Stop here.

Otherwise, read the upstream plugin manifest **without checking it out**:

```
git -C <mkt> show origin/main:.claude-plugin/plugin.json
```

Extract `newVersion` from the JSON. If parsing fails → abort: *"Could not read plugin.json on origin/main. The remote may be malformed."*

### 3. Show incoming changes

Display:

```
git -C <mkt> log --oneline --no-decorate HEAD..origin/main
git -C <mkt> diff --stat HEAD..origin/main
```

Cap the log at 20 commits and the diffstat at 30 lines — collapse the rest with `... + N more`.

Also display the version delta:

```
Version: <installedVersion> → <newVersion>
   (note: if these are equal but commits differ, the maintainer pushed
   changes without bumping plugin.json — upgrade is still safe, but
   Claude Code may not register the cache as outdated.)
```

### 4. Human confirmation (required)

Pause and ask explicitly:

```
Pull these N commits into the marketplace clone? (yes / no)
```

Wait for a clear affirmative answer. Anything else → abort cleanly: `Upgrade aborted — no changes made.`

### 5. Fast-forward pull

```
git -C <mkt> pull --ff-only origin main
```

If this fails (diverged history, force-pushed upstream) → abort with the git error verbatim and:

```
⚠ Fast-forward pull failed. The marketplace clone has diverged from
   origin/main. Resolve manually — typically with
   `git -C <mkt> reset --hard origin/main` — and re-run /craft:upgrade.
   Auto-recovery is intentionally disabled.
```

---

## Post-Assertions

### P1 — HEAD matches origin/main

```
git -C <mkt> rev-parse HEAD
git -C <mkt> rev-parse origin/main
```

Equal → continue. Mismatch → warn loudly: *"⚠ Post-pull SHA mismatch — the pull may have only partially completed. Inspect `<mkt>` manually."*

### P2 — Version readable

- Read `<mkt>/.claude-plugin/plugin.json`.
- Extract `version` → must equal the `newVersion` recorded in Procedure step 2. If different → warn: *"⚠ plugin.json version (<X>) does not match what was previewed (<Y>). Re-run /craft:upgrade to re-sync."*

### P3 — Marketplace manifest version (informational)

- Read `<mkt>/.claude-plugin/marketplace.json`.
- If the `plugins[0].version` does not match `newVersion` from plugin.json → emit an informational note: *"⚠ marketplace.json and plugin.json disagree on version. Probably a release-prep oversight in the upstream repo; harmless for the upgrade itself."*

---

## Output Format

Successful upgrade:

```
✓ Marketplace: <marketplaceName> at <mkt>
✓ Pre-assertions: clean, on main, installedVersion=<X>
✓ Pulled N commits (<oldSHA> → <newSHA>), version <X> → <Y>
✓ Post-assertions: HEAD=origin/main, plugin.json=<Y>

⟳ Restart your Claude Code session to install the new version.
   If Claude Code does not auto-reinstall on restart, run
   `/plugin update craft@<marketplaceName>` from inside the new session.
```

Already up to date:

```
Already on latest (<installedVersion>, commit <short SHA>). Nothing to do.
```

Aborted:

```
Upgrade aborted — <reason>. No changes made.
```

---

## Error Handling

| Situation | Behavior |
|---|---|
| `craft@<marketplace>` not in `installed_plugins.json` | Abort with non-marketplace-install hint. |
| Multiple installed entries (user + project scopes) | Prefer user scope; if ambiguous, abort and list candidates. |
| Marketplace clone directory missing | Abort with reinstall hint. |
| `<mkt>/.git` missing | Abort — refuse to operate on a non-git directory. |
| `marketplace.json` does not list `craft` | Abort — refuse to upgrade a foreign marketplace. |
| Working tree dirty | Abort, show first 10 lines of porcelain, do not stash. |
| Branch is not `main` | Abort with `git checkout main` hint. |
| No `origin` remote | Abort with setup hint. |
| `git fetch` network failure | Abort with the git error verbatim. |
| `origin/main` plugin.json unreadable or invalid JSON | Abort. |
| User confirmation not affirmative | Clean abort, no mutation. |
| `pull --ff-only` fails | Abort with manual-recovery hint. Do not auto-resolve. |
| Post-pull SHA mismatch | Warn loudly; user inspects manually. |
| Plugin/marketplace version disagree | Informational note only; do not abort. |

---

## What This Command Does NOT Do

- It does **not** modify the plugin cache (`~/.claude/plugins/cache/...`). Claude Code re-installs from the marketplace on session start; we do not duplicate that logic here.
- It does **not** edit `~/.claude/plugins/installed_plugins.json`. That file is Claude Code's source of truth and must stay under its control.
- It does **not** bump the plugin version, create a git tag, or push anything. Releasing CRAFT is a manual maintainer workflow.
- It does **not** rebase, force-push, reset --hard, or auto-resolve diverged histories. Recovery is always a human-initiated step.
- It does **not** sync any other plugin (context-mode, context7, etc.). Use their own upgrade commands.
- It does **not** restart the Claude Code session for the user. Claude Code does not provide a programmatic restart from inside a session; the user must do it themselves.
- It does **not** offer a "force" or "skip confirmation" mode. Every upgrade is a durable mutation under explicit human control.
