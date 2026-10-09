# Zu CRAFT beitragen

*In English: [CONTRIBUTING.md](./CONTRIBUTING.md)*

Danke, dass du CRAFT verbessern willst. Dieser Leitfaden erklärt, wie das Plugin gebaut ist, wie du deine Kopie davon
ausführst, welche Prüfungen grün bleiben müssen und wie eine Änderung in ein Release kommt.

CRAFT wird mit CRAFT gebaut: Jede Änderung durchläuft dieselbe Phasenschleife, die das Plugin ausliefert — planen, bauen,
prüfen, zusammenfassen, reviewen, committen. Du musst CRAFT nicht benutzen, um einen Fix zu schicken, aber die Schleife
erklärt, warum das Repository so aussieht, wie es aussieht.

---

## Ein Problem melden oder eine Änderung vorschlagen

- **Bugs und Ideen:** Öffne ein Issue unter [github.com/ChriRas/craft/issues](https://github.com/ChriRas/craft/issues).
  Schreib, was du ausgeführt hast, was du erwartet hast und was passiert ist — der Statusblock von `/craft:prime` und die
  CRAFT-Version (`CRAFT plugin v…`) helfen sehr.
- **Kleine Fixes** (ein Tippfehler, ein falscher Pfad, ein kaputter Link): Ein Pull Request ist direkt willkommen.
- **Größere Änderungen** (ein neues Command, eine geänderte Workflow-Regel, ein neuer Helper): Öffne zuerst ein Issue.
  CRAFT hält jede Architekturentscheidung als nummerierten Eintrag (`D1`–`D42`) in
  [`brainstorm-decisions.md`](./brainstorm-decisions.md) fest, *bevor* sie gebaut wird — ein Designgespräch vorab erspart
  dir Nacharbeit.

Mit deinem Beitrag stimmst du zu, dass deine Arbeit unter der [MIT-Lizenz](./LICENSE) veröffentlicht wird.

---

## Was du brauchst

Dieselben Werkzeuge, die CRAFT selbst voraussetzt (siehe README → *Requirements*): Claude Code, `git`, `gh`,
`bash` ≥ 5.0, `python3`, das Plugin `context-mode` und die CLI `agent-browser`. Die Bash-Harnesses laufen ohne Claude
Code; nur die Headless-Probes und `claude plugin validate .` brauchen es.

---

## Deine Arbeitskopie als Plugin ausführen

Eine normale Claude-Code-Session führt das **installierte** CRAFT aus — eine Kopie in
`~/.claude/plugins/cache/craft/craft/<version>/` —, nicht die Dateien, die du gerade bearbeitest. Eine Änderung an einem
Command wirkt deshalb nicht in der Session, die sie macht. Um deinen Arbeitsbaum auszuführen, starte eine neue Session
mit:

```bash
claude --plugin-dir /path/to/your/craft/clone
```

In dieser Session meldet `/craft:prime` `✓ Plugin runtime = working tree (loaded in place)`. In einer normalen Session in
diesem Repository warnt es `⚠ Plugin runtime ≠ working tree` und nennt die Dateien, die sich unterscheiden.

**Headless-Probes** (`claude -p "/craft:<command>" --plugin-dir <kopie>`) zeigen, was geänderte Command-Prosa
tatsächlich tut. Starte sie aus einer Scratch-Kopie außerhalb dieses Repositorys, einen nach dem anderen: Ein
verschachteltes `claude`, das im Repository startet, führt den SessionStart-Hook aus und nimmt der Session, in der du
arbeitest, das Priming. Beurteile einen Probelauf nach dem, was er hinterlassen hat — git-Historie, Dateien, das Transkript
—, nie nach dem Bericht des geprüften Agents. Lass einen Probelauf nie ein Modell wählen, das Usage-Credits abrechnen kann.

---

## Aufbau des Repositorys

| Pfad | Was dort liegt |
|---|---|
| `commands/` | Die Slash-Commands (`/craft:<name>`), je eine Markdown-Datei. |
| `skills/` | Skills: der Workflow, die Senior-Developer-Baseline, `/craft`, `/craft:debug`, brainstorm, grill-me, Stack-Packs. |
| `agents/` | Subagents: `slice-builder`, `code-reviewer`, `slice-planner`, `plan-architect`. |
| `hooks/` | Bash-Hooks und `hooks.json` (SessionStart, PreToolUse, UserPromptSubmit). |
| `scripts/` | Helper-Skripte, die die Commands aufrufen, und die `test-*.sh`-Harnesses. |
| `templates/` | Vorlagen, die `/craft:onboard`, `/craft:plan` und `/craft:commit` ausfüllen, und die Profil-Presets. |
| `docs/` | Die zweisprachige Dokumentationsseite (GitHub Pages). |
| `model-defaults.md`, `craft-profile-defaults.md` | Die einzigen Deklarationen der Modellwerte und Profil-Defaults. |
| `.claude/project/` | CRAFTs eigenes Projektwissen (Intent, Regeln, Roadmap) und das Archiv jedes fertigen Slice. |

---

## Die Prüfungen, die grün bleiben müssen

Es gibt kein klassisches Test-Framework — CRAFT liefert Markdown, JSON und Bash aus. Stattdessen decken eigenständige
Bash-Harnesses in `scripts/test-*.sh` die Helper, die Hooks, den Phasengraphen, den die Command-Prosa abbildet, und die
Docs-Seite ab. Jeder ist in [`CLAUDE.md`](./CLAUDE.md) → *Common Commands* beschrieben. Führ sie alle aus, dazu die
Manifest-Prüfung:

```bash
for f in scripts/test-*.sh; do bash "$f" >/dev/null 2>&1 || echo "RED: $f"; done
```

```bash
claude plugin validate .
```

`scripts/test-model-enum.sh` läuft 8–10 Minuten (es kopiert das Repository für jede Mutations-Fixture); die anderen
brauchen Sekunden. Eine Änderung an `docs/` oder an einem Plugin-Bestandteil muss `scripts/test-docs-site.sh` grün
halten — es vergleicht die Docs-Seite mit der Oberfläche des Plugins.

---

## Konventionen

- **Commits** folgen Conventional Commits: `<type>(<scope>): <subject>` — `feat`, `fix`, `docs`, `test`, `refactor`,
  `chore`. Eine logische Änderung pro Commit; Code und Doku werden getrennt committet. Kein `Co-Authored-By`-Trailer.
- **Prosa ist nicht prüfbar — Marker schon.** Command-Dateien tragen maschinenlesbare Marker
  (`<!-- craft:writes … -->`, `<!-- craft:reads … -->`, `<!-- craft:choice -->`, `<!-- craft:handoff … -->` …), die die
  Harnesses binden. Wenn du einen Status-Schreibvorgang, eine menschliche Entscheidung oder ein Handoff hinzufügst, setz
  seinen Marker, sonst wird ein Harness rot.
- **Eine Regel wird nie zweimal beschrieben.** Brauchen zwei Stellen dieselbe Regel, definiert eine sie und die andere
  verweist darauf. Wo eine Kopie nicht weg kann (eine Vorlage, die Docs-Seite), wird sie *gebunden*: Sie trägt einen
  Marker, und ein Harness vergleicht sie mit der einen Deklaration.
- **Abgeleiteter Zustand statt Aufräumen.** Ob etwas noch gilt, liest ein Helper aus dem Slice-Plan oder aus git — es
  steht nicht in einem Flag, das jeder Schreiber zurücksetzen müsste.
- **Hooks bleiben bash-3.2-kompatibel** (macOS `/bin/bash`), ebenso die Helper, die ein Hook aufruft; der Rest von
  `scripts/` darf bash ≥ 5.0 nutzen.
- **Kein Löschbefehl in einer Zeile, die der Agent absetzt** — ein Helper behält sein eigenes `rm` im Skript. Eine
  Regel des Users zum Löschen von Dateien ist seine Grenze.
- **Zahlen werden von einem Lauf abgelesen, nie hergeleitet** — Fixture-Zahlen, Check-Zahlen, Zeilenzahlen.
- **Code-Kommentare und Doku sind auf Englisch**; die Docs-Seite ist zweisprachig (Englisch und Deutsch), und beide
  Sprachen bleiben gleichwertig.

---

## Dokumentation

- **README.md** — Überblick und Quickstart.
- **CHANGELOG.md** — [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Neue Einträge kommen unter `[Unreleased]`,
  **ein Eintrag pro Zeile**: Die GitHub-Release-Notes werden aus diesem Abschnitt erzeugt, und ein umbrochener Eintrag
  würde dort zu einem harten Zeilenumbruch. `test-docs-site.sh` prüft das.
- **docs/index.html** — die Dokumentationsseite. Ihr redaktioneller Vertrag, ihre Struktur und das Vorgehen beim
  Aktualisieren stehen in `.claude/skills/docs-site/SKILL.md`; `test-docs-site.sh` hält Badge, Zahlen und
  Harness-Tabelle mit dem Baum im Gleichschritt.

---

## Wie ein Release entsteht

CRAFT folgt [Semantic Versioning](https://semver.org/lang/de/). Die `version` in `.claude-plugin/plugin.json` ist der
Update-Schlüssel von Claude Code — ein Update auf eine Version, die schon installiert ist, wird übersprungen, deshalb
**hebt jedes Release sie an**.

1. Den Abschnitt `[Unreleased]` im CHANGELOG unter eine neue Überschrift `## [X.Y.Z] - <datum>` verschieben und
   darüber eine leere Überschrift `## [Unreleased]` stehen lassen (`scripts/test-docs-site.sh` verlangt sie); ein
   Zwischenrelease mit einer brechenden Verhaltensänderung beginnt seinen Abschnitt mit einem Upgrade-Hinweis.
2. `version` in `.claude-plugin/plugin.json`, beide `version`-Felder in `.claude-plugin/marketplace.json` und das
   Versions-Badge der Docs-Seite anheben; alle Harnesses ausführen.
3. `main` pushen — der Marketplace installiert `main` in seinem HEAD-Stand, also **ist der Push das Release**.
4. Den gepushten Commit taggen und das GitHub-Release aus dem CHANGELOG-Abschnitt anlegen:

```bash
git tag -a vX.Y.Z origin/main -m "vX.Y.Z"
```

```bash
git push origin vX.Y.Z
```

Nutzer aktualisieren dann mit `/craft:upgrade` (es synchronisiert den Marketplace-Klon) und
`/plugin update craft@craft`; eine neue Session lädt die neue Version.
