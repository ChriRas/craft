# Brainstorm — Skill-Shortname-Pattern (`/context-mode` statt `/context-mode:context-mode`)

**Status:** Research finding, awaiting brainstorm.
**Source:** `Research/context-mode/` analysis, 2026-05-19.

## Beobachtung

Context-mode hat **keinen einzigen Slash-Command** im klassischen Sinn — kein `commands/` Verzeichnis im Plugin. Alles läuft über zwei Mechanismen:

1. **MCP-Tools** (via `mcpServers` in `plugin.json` → `start.mjs`)
2. **Skills** in `skills/<name>/SKILL.md`

Trotzdem ist `/context-mode` als Slash-Command aufrufbar.

## Mechanismus

**Plugin-Name == Skill-Name = Namespace-Kollaps.**

```json
// .claude-plugin/plugin.json
{ "name": "context-mode", ... }
```

```yaml
# skills/context-mode/SKILL.md
---
name: context-mode
description: |
  Use context-mode tools (ctx_execute, ctx_execute_file)...
  Triggers: "analyze logs", "summarize output", ...
---
```

Vollform `/context-mode:context-mode` → Claude Code erlaubt die Kurzform `/context-mode`, wenn Plugin- und Skill-Name identisch sind.

## Das `user-invocable`-Flag

Die anderen Skills (`ctx-doctor`, `ctx-upgrade`, `ctx-stats`, `ctx-purge`, `ctx-insight`) sind über Frontmatter-Flag als Slash-Commands aufrufbar:

```yaml
---
name: ctx-upgrade
description: |
  Update context-mode from GitHub and fix hooks/settings.
  Trigger: /context-mode:ctx-upgrade
user-invocable: true
---
```

- `user-invocable: true` macht den Skill explizit zum Slash-Command.
- Der Basis-`context-mode` Skill hat das NICHT — er läuft über Description-Trigger (Auto-Activation durch Keywords).
- Aber: Plugin=Skill-Name-Kollaps funktioniert trotzdem.

## Vergleich: Status quo CRAFT

CRAFT verwendet aktuell:
- 17 Slash-Commands in `commands/<name>.md`
- Shim-Files in `~/.claude/commands/<name>.md` für Kurzform `/onboard` statt `/craft:onboard`
- Skills nur für nicht-User-invocable Logik (workflow, self-verify, brainstorm, grill-me)

## Implikationen / Brainstorm-Fragen

1. **Könnten wir die 17 Commands zu Skills mit `user-invocable: true` konvertieren?**
   - Vorteil: Shim-Files entfallen, ein einziges System
   - Vorteil: Skills können auch Description-Trigger haben (Auto-Activation)
   - Frage: Was geht verloren? Commands haben `$ARGUMENTS`, kann ein Skill das?
   - Frage: Können Skills Bash-Befehle ausführen wie Commands?

2. **Sollten wir einen Top-Level-Skill `craft` (mit `name: craft`) anlegen?**
   - Aufrufbar als `/craft` durch Namespace-Kollaps
   - Funktion: Status, Phase-Picker, Onboarding-Trigger
   - Auto-Activation via Description-Trigger ("we're starting a slice", "next phase", ...)
   - Spart einen zusätzlichen Command

3. **Verhältnis Commands vs. Skills bei CRAFT klären:**
   - Commands = explizite, parametrisierte User-Aktionen?
   - Skills = Verhalten/Wissen, das der Agent automatisch anwendet?
   - Oder: alles Skills, mit `user-invocable: true` wo nötig?

4. **Risiken:**
   - Skill-Definitionen sind länger als Command-Definitionen (YAML + Body)
   - Auto-Activation kann unerwünscht feuern, wenn Description zu breit
   - Plugin=Skill-Name-Kollaps ist evtl. undokumentiertes CC-Verhalten — riskant?

## Zu validieren

- [ ] CC-Doku: Ist Plugin=Skill-Name-Kollaps offiziell unterstützt oder Implementations-Detail?
- [ ] Kann ein Skill mit `user-invocable: true` Argumente entgegennehmen (analog `$ARGUMENTS`)?
- [ ] Können Skills genauso Hooks/Bash auslösen wie Commands?
- [ ] Was passiert bei Konflikten — `/craft` Skill UND `~/.claude/commands/craft.md` Shim?

## Nächster Schritt

Brainstorm-Session zur Entscheidung: **Commands behalten, Hybrid, oder voll auf Skills migrieren?**
Vor der Entscheidung Doku-Recherche + ein kleiner Spike (1 Command → Skill konvertieren) sinnvoll.
