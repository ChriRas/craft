# Brainstorm — Context-Mode Update-Mechanismus

**Status:** Research finding, awaiting brainstorm.
**Source:** `Research/context-mode/` analysis, 2026-05-19.
**Key files inspected:**
- `Research/context-mode/skills/ctx-upgrade/SKILL.md`
- `Research/context-mode/src/server.ts` (lines 3002–3110, `ctx_upgrade` MCP tool)
- `Research/context-mode/src/cli.ts` (lines 675–970, `upgrade()` function)
- `Research/context-mode/package.json`
- `Research/context-mode/.claude-plugin/plugin.json`

## Architektur — Dreischichtiges Update

### Schicht 1 — Skill `ctx-upgrade` (`skills/ctx-upgrade/SKILL.md`)

Mini-Anweisung an den Agent. Frontmatter:

```yaml
---
name: ctx-upgrade
description: |
  Update context-mode from GitHub and fix hooks/settings.
  Pulls latest, builds, installs, updates npm global, configures hooks.
  Trigger: /context-mode:ctx-upgrade
user-invocable: true
---
```

Body sagt dem Agent:

1. MCP-Tool `ctx_upgrade` aufrufen — gibt einen Shell-Command zurück.
2. Shell-Command via Bash ausführen.
3. Ergebnis als Markdown-Checkliste anzeigen (`[x]`/`[ ]` mit Versionen).
4. User-Hinweis: **Session-Restart** erforderlich.
5. **Fallback** wenn MCP-Tool versagt: Plugin-Root aus dem Skill-Pfad ableiten (2 Ebenen hoch), `cli.bundle.mjs` oder `build/cli.js` direkt aufrufen.

### Schicht 2 — MCP-Tool `ctx_upgrade` (`src/server.ts:3002`)

Führt selbst **nichts** aus. Konstruiert einen Shell-Command-String und gibt ihn zurück.
Drei Fallback-Pfade:

- Primär: `node <plugin-root>/cli.bundle.mjs upgrade`
- Fallback: `node <plugin-root>/build/cli.js upgrade`
- Notfall: Selbstgenerierter Inline-Node-`-e`-Script — Plugin-Root vom CLI nicht auffindbar → Inline-Script clont das Repo, baut und installiert. Schreibt in `/tmp/ctx-upgrade-XXXXX/` und führt aus.

Zusätzlich: Cleanup von `insight-cache` (best-effort, blockt nie).

### Schicht 3 — `cli.ts:upgrade()` — Das eigentliche Update

Ausführungs-Reihenfolge (`src/cli.ts:675`):

1. **Plattform-Detection + Adapter laden** (`detectPlatform()` — Claude Code vs. Gemini CLI vs. OpenCode vs. Kilo)

2. **Marketplace-Clone syncen** (`~/.claude/plugins/marketplaces/context-mode/`):
   - Nur wenn `.git` vorhanden
   - `git status --porcelain` prüfen — User-Edits respektieren (skip wenn dirty)
   - `git fetch --tags origin` + `git reset --hard origin/HEAD`
   - Bei Fehler: Warning + manuelle Anleitung

3. **Frische Kopie clonen** in `tmpdir()/context-mode-upgrade-<ts>/`:
   - `git clone --depth 1 https://github.com/mksglu/context-mode.git`

4. **Versionsvergleich:**
   - `localVersion` aus eingebauter `package.json`
   - `newVersion` aus tmp-Clone-`package.json`
   - Wenn gleich → cleanup tmp, exit "Already on latest"

5. **Build im tmp-Clone:**
   - `npm install --no-audit --no-fund` (timeout 120s)
   - `npm run build` (timeout 60s)

6. **In-place Copy** ins live `pluginRoot`:
   - Liest `files`-Array aus der **geclonten** `package.json` (Henne/Ei-Schutz: neue Dirs wie `insight/` werden automatisch übernommen, ohne dass die alte CLI sie kennen muss)
   - Plus zusätzlich `src` und `package.json`
   - Pro Item: `rmSync` + `cpSync`

7. **`.mcp.json` schreiben** mit `${CLAUDE_PLUGIN_ROOT}` Platzhalter:
   - **Nicht** absoluter Pfad — der könnte gelöscht werden, wenn die alte Version-Dir aufgeräumt wird (Issue #181)
   - Platzhalter wird von Claude Code zur Laufzeit aufgelöst

8. **Pre-flight check:**
   - `plugin.json` von Disk lesen
   - Vergleichen mit `newVersion`
   - Throw bei Mismatch — Schutz vor v1.0.113-class Drift (rsync race, partial write)

9. **Registry-Update** in `~/.claude/plugins/installed_plugins.json`:
   - Via `adapter.updatePluginRegistry(pluginRoot, newVersion)` (adapter-spezifisch)

10. **Post-write Assertion:**
    - `installed_plugins.json` re-read
    - Pro `entry`: `installPath` muss existieren, `installPath/.claude-plugin/plugin.json` muss `newVersion` haben
    - Throw bei Mismatch — fail loud, nicht silent drift

11. **Marketplace-Clone Post-Assertion:**
    - Falls vorhanden, `<marketplace>/.claude-plugin/plugin.json` muss `newVersion` haben
    - Bei Mismatch: Warning + manuelle Fix-Anleitung (`git -C <dir> fetch && reset --hard`)

12. **`npm install --production --no-audit --no-fund`** im `pluginRoot`

13. **Native-Addon-ABI-Check** (better-sqlite3):
    - Nur Claude Code / Gemini (nicht opencode/kilo)
    - Lädt `hooks/ensure-deps.mjs` dynamisch mit Cache-Buster (`?upgrade=<ts>`)
    - Prüft, ob `better_sqlite3.abi<NODE_MODULES>.node` vorhanden ist
    - Bei Fehler: Warning + manuelle Anleitung (`npm rebuild better-sqlite3`)

14. **`npm install -g <pluginRoot>`** (global npm sync, best-effort)

15. **Cleanup tmp** + **Skills sync** zu allen Installations-Pfaden aus der Registry

16. User-Hinweis: **Session-Restart** erforderlich

## Defensive Patterns — Was hier stark ist

- **MCP-Tool produziert nur Strings, Agent führt aus** → klare Separation: Logik deklarativ, Ausführung sichtbar im Tool-Call. Passt zu `feedback-human-control`.
- **Drei Fallback-Pfade** (primary CLI, fallback CLI, inline node -e) — robust gegen unbekannten Install-Zustand.
- **`files`-Array aus dem geclonten package.json lesen** — Henne/Ei-Pattern: das *Neue* sagt der *Alten*, was zu kopieren ist.
- **`${CLAUDE_PLUGIN_ROOT}` Platzhalter** statt absoluter Pfad in `.mcp.json` — überlebt Cleanup-Races.
- **Pre-flight + Post-write Assertions** — silent drift wird explizit verboten, lieber Throw als unbemerkter Bug.
- **`git status --porcelain` Check** vor `git reset --hard` — User-Edits respektieren.
- **Marketplace + Plugin-Root + npm-global** als drei separate Konsistenz-Ziele — alle drei werden geprüft und gesynct.

## Vergleich zu CRAFT — Was ist relevant?

| Context-mode hat | CRAFT hat | Relevanz |
|---|---|---|
| Bundled CLI (`cli.bundle.mjs`) | nein | nein |
| MCP-Server (`server.bundle.mjs`) | nein | nein |
| Native Addons (better-sqlite3) | nein | nein |
| npm global installation | nein | nein |
| Marketplace-Distribution | unklar/geplant? | später |
| `files`-Array Update-Pattern | n/a | n/a |
| **Skill als Upgrade-Trigger** | ja, übertragbar | **hoch** |
| **MCP-Tool als Shell-Command-Generator** | nein, aber Pattern übertragbar | **mittel** |
| **Pre/Post-Assertions beim Update** | nein | **hoch** |
| **Marketplace-Clone Sync** | n/a aktuell | später |

## Minimal-Variante für CRAFT

Da CRAFT keine Build-Pipeline und keinen MCP-Server hat, reicht für `/craft:upgrade` deutlich weniger:

```
1. cd <plugin-root>
2. git status --porcelain → wenn dirty: warnen, abbrechen (kein silent stash)
3. git fetch origin
4. Versionsvergleich (jetzt vs. origin/HEAD)
5. Wenn gleich → "Already on latest"
6. git pull --ff-only
7. claude plugin validate (Schema-Check)
8. User-Hinweis: Session-Restart
```

Spätere Erweiterungen:
- Marketplace-Distribution (wenn CRAFT in einen Marketplace kommt)
- Update-Cache für Versions-Check ohne Netzwerk
- Hook-Re-Installation falls SessionStart-Hook gerendet
- Adapter für andere CC-Clients (Gemini CLI etc.)

## Brainstorm-Fragen

1. **Lohnt sich für CRAFT ein eigener `/craft:upgrade` überhaupt?**
   - Alternative: User macht `git pull` manuell, das ist's
   - Pro `/upgrade`: konsistente UX, Validate-Schritt erzwungen, Session-Restart-Hinweis automatisch
   - Contra: zusätzlicher Code, der nur `git pull` wrapped

2. **Sollten wir die Pre/Post-Assertion-Pattern übernehmen?**
   - z.B. nach `/prime` prüfen, ob `intent.md` + `rules.md` + `CLAUDE.md` konsistent sind?
   - Generalisierung: jeder durable-state-changing Command bekommt Pre/Post-Assertions

3. **Marketplace-Strategie:**
   - Aktuell: CRAFT ist lokal, kein Marketplace
   - Wenn CRAFT in den offiziellen CC-Marketplace kommt: ähnliche Sync-Mechanik nötig
   - Sollte das Architecture-Spec ergänzt werden? (D17 spricht von Tool-Dependencies, nicht Distribution)

4. **MCP-Tool-Pattern für andere Commands?**
   - `ctx_doctor`/`ctx_stats` etc. sind MCP-Tools, weil context-mode eh einen MCP-Server hat
   - CRAFT hat keinen MCP-Server. Lohnt sich einer? (Persistente Slice-State-Queries, Phase-Tracking ohne Filesystem-Scan)
   - Risiko: Komplexität explodiert, CRAFT verliert "Plugin = nur Markdown"-Charme

## Nächster Schritt

Brainstorm-Session: **Welche Update-Strategie passt zu CRAFT's "Plugin = nur Markdown"-Philosophie?**
Vermutlich Minimal-Variante (`git pull` + validate), aber die Defensive-Patterns (Pre/Post-Assertions, User-Edits respektieren) sind unabhängig davon übernehmbar.
