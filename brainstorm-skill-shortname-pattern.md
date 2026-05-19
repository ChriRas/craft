# Brainstorm — Skill-Shortname-Pattern (`/context-mode` statt `/context-mode:context-mode`)

**Status:** Decided 2026-05-19.
**Source:** `Research/context-mode/` analysis, 2026-05-19 (initial), official Claude Code docs via context7, 2026-05-19 (validation).

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

---

## Findings (Recherche 2026-05-19, via context7 → `/anthropics/claude-code` + `/websites/code_claude`)

### Was der Brainstorm richtig hatte
- Plugin-Skills sind als Slash-Commands aufrufbar (`/plugin-name:skill-name`).
- Skills können in der Form `/plugin-name:skill-name` exakt wie Commands genutzt werden.
- Skill-Body kann Bash injizieren (`` !`command` ``).

### Was korrigiert werden muss
- **`user-invocable` ist invertiert verstanden worden.** Default ist `true` (Skill ist user- *und* model-invocable). `user-invocable: false` macht den Skill zu reinem Background-Wissen ohne Slash-Trigger. Es ist also nicht das Flag, mit dem man Skills "zum Slash-Command macht" — sie sind es standardmäßig.
- **Das richtige Flag für "manueller Trigger only, kein Auto-Invoke durch Claude"** ist `disable-model-invocation: true`. Gilt für Commands UND Skills identisch.
- **Skill-Argumente:** voll unterstützt (`$ARGUMENTS`, `$1`/`$2`, `argument-hint:`). Quelle: `code.claude.com/docs/en/plugins` → "Add Skill Arguments".
- **Skill-Frontmatter:** akzeptiert dieselben Felder wie Commands (`description`, `allowed-tools`, `model`, `argument-hint`, `disable-model-invocation`, `user-invocable`).
- **Plugin-Name == Skill-Name Kollaps zu `/plugin-name`:** offiziell **undokumentiert**. Funktioniert empirisch (`/context-mode`), darf aber nicht als versprochenes Verhalten dokumentiert werden. Kanonische Form bleibt `/plugin-name:skill-name`.
- **Skill ↔ User-Command-Kollision** (`~/.claude/commands/<name>.md` vs. Plugin-Skill): Präzedenz-Reihenfolge **undokumentiert**. Konsequenz: keine User-Shims setzen.

## Entscheidung

### Aufteilung 14 → 11 Commands + 3 Skills

**Bleiben Commands** (explizite Human-Control-Gates, niemals Auto-Trigger):

| Command | Rolle |
|---|---|
| `/craft:onboard` | One-shot Bootstrapping |
| `/craft:prime` | Manual Re-Prime (auch Hook-getrieben) |
| `/craft:status` | Read-only Pull |
| `/craft:continue` | Slice-Resume mit Arg |
| `/craft:pause` | Slice-Pause |
| `/craft:abort` | Destruktiver Abbruch |
| `/craft:handoff` | Context-Reset-Signal |
| `/craft:intent-update` | Human-Control-Gate für Intent |
| `/craft:plan` | Phase-3-Gate |
| `/craft:execute` | Phase-4-Gate |
| `/craft:test` | Phase-5-Gate |
| `/craft:recap` | Phase-6-Gate |
| `/craft:refactor` | Phase-7-Gate |
| `/craft:commit` | Phase-8-Gate |

**Werden Skills** (wrappen bereits existierende Skills bzw. profitieren von Auto-Activation):

| Migration | Frontmatter-Strategie |
|---|---|
| `commands/brainstorm.md` → `skills/craft/brainstorm/SKILL.md` (oder bestehender Skill um Slash-Eintrag erweitert) | `disable-model-invocation: true` — Slash only, keine Auto-Activation (Risiko: falsch-triggert bei beiläufiger Ideen-Erwähnung) |
| `commands/grill-me.md` → entsprechender Skill | `disable-model-invocation: true` — gleicher Grund |
| `commands/debug.md` → `skills/debug/SKILL.md` (renamed from `self-verify`) | **Auto-Activation erwünscht** — Description-Trigger für "2+ fix attempts", "let me debug" |

### Begründung
- Phase-Commands sind explizite Workflow-Übergänge → Auto-Activation wäre ein Anti-Pattern gegen "Human keeps control".
- Die 3 Skill-Kandidaten wrappen bereits bestehende Skills oder wollen den Auto-Trigger explizit nutzen (`debug`).
- `/craft` als state-aware Entry bleibt der einzige Top-Level-Skill (bereits implementiert).

### Verworfen
- **Voll-Migration aller Commands zu Skills:** zu hohes Risiko ungewollter Auto-Triggerings für Phase-Gates.
- **`~/.claude/commands/<name>.md` Shims für Kurzformen:** Kollision mit Plugin-Resolver undokumentiert — Risiko zu hoch.
- **Sich auf `/plugin-name` Kurzform verlassen:** undokumentiertes Verhalten, nur als Komfort betrachten.

## Folge-Schritte

1. ~~Entscheidung als Update in `brainstorm-skill-shortname-pattern.md` festhalten~~ ✅ (dieses Dokument)
2. ~~**Spike:** `debug` als erstes auf Skill konvertieren~~ ✅ (Commit `27db6e0`)
3. ~~Bei Erfolg: `brainstorm` + `grill-me` migrieren~~ ✅ (dieser Commit) — beide mit `disable-model-invocation: true`, CRAFT-spezifische Slash-Sektion in den Skill-Body integriert.
4. ~~README ergänzen: `context7` und `context-mode` als "recommended companion plugins" dokumentieren~~ ✅ (dieser Commit)
5. Optional: `prime` Hybrid-Refactor (Skill mit Hook + manual Command) — geringe Priorität.
