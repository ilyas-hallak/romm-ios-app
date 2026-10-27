---
description: Review eines Pull Requests nach den Projektregeln, setzt danach das Reviewed-Gate im PR
argument-hint: "[PR-Nummer, ohne Angabe der PR des aktuellen Branches]"
---

Review eines Pull Requests nach den Regeln in `CLAUDE.md`.

Argument vom User (optional): $ARGUMENTS

## 1. PR bestimmen

Mit Nummer: diese nehmen. Ohne Nummer: `gh pr view --json number,title,body,headRefName` für den aktuellen Branch. Findet sich keiner, offene PRs listen und auswählen lassen.

## 2. Vorbedingung prüfen

Den Status-Block im PR-Body lesen. Ist "Manually tested" noch nicht gesetzt, einmal kurz nachfragen, ob trotzdem reviewt werden soll. Der Review kommt normalerweise nach dem manuellen Test.

## 3. Diff holen

`gh pr diff <n>` plus die geänderten Dateien (`gh pr view <n> --json files`). Bei großen Diffs die Dateien nach Thema gruppieren, nicht alles in einen Prompt kippen.

## 4. Prüfung auf Subagents verteilen

Drei Sonnet-Subagents parallel, jeder mit vollem Briefing, weil er diese Unterhaltung nicht sieht. Jeder bekommt den Diff-Teil, den er braucht, den Auftrag, Findings mit `datei:zeile` und konkretem Vorschlag zu liefern, und die Anweisung, nichts zu ändern.

1. **Korrektheit und Architektur**: Bugs, falsche Logik, Edge Cases, Race Conditions, Force-Unwraps. Dazu die Layer-Regeln aus `CLAUDE.md`: Abhängigkeitsrichtung, UseCase ruft keinen UseCase, Protokolle für Testbarkeit. Domain importiert Foundation, nie UIKit, alles was `UIScreen` oder `AVAudioSession` liest gehört in die UI. Zu jeder neuen Abhängigkeit drei Fragen:
   - Kommt sie über den Initialisierer? Eine setzbare Property mit Singleton-Default ist Property Injection, die kann zur Laufzeit jeder umbiegen. Gilt auch für UIKit-Views, die meist genau eine Erzeugungsstelle haben.
   - Ist sie in `PDependencyFactory` registriert? Das etablierte Muster ist `init(factory: PDependencyFactory = DefaultDependencyFactory.shared)`. Ein Default direkt auf ein `Something.shared` ist die Ausnahme und muss begründet werden.
   - Ersetzt ein Test sie wirklich? Ein Protokoll samt Injection, das kein Test je austauscht, ist Abstraktion auf Vorrat. Lautet die Antwort "keiner", dann entweder den Test schreiben oder die Naht wieder ausbauen.
2. **Clean Code und Kommentare**: Methodengröße, Parameteranzahl, Namen, Duplizierung, Over-Engineering. Kommentare auf Englisch, kurz, nur wo nötig, Noise markieren.
3. **Tests**: Sind kritische Pfade und echte Logik abgedeckt, ist neuer Test-Code Swift Testing, fehlen Protokoll-Abstraktionen, die Tests überhaupt erst möglich machen.

## 5. Ergebnis zusammenführen

Selbst bewerten, nicht die Subagent-Ausgaben durchreichen. Fehlalarme rauswerfen, Duplikate zusammenziehen, priorisieren: Bugs vor Architektur vor Cleanup vor Kommentaren. Ergebnis kurz auf Deutsch vorlegen, mit `datei:zeile`.

Von sich aus nichts ändern. Fixes erst auf Zuruf, und dann bevorzugt über einen Haiku-Subagent, wenn die Änderung mechanisch ist.

## 6. Nach den Fixes erneut prüfen

Code, der erst beim Beheben der Findings entsteht, ist selbst noch nicht reviewt. Die Fragen aus Schritt 4 danach auf genau diesen neuen Code anwenden, vor allem die zu Dependency Injection und zu Tests. Was dabei eingeführt wurde, im Bericht benennen, auch ungefragt. Ein Fix ist kein Freibrief für das, was er mitbringt.

## 7. Gate setzen

Erst wenn die Findings erledigt oder bewusst abgelehnt sind, im PR-Body "Reviewed" abhaken:

```bash
gh pr edit <n> --body "<Body mit gesetzter Checkbox>"
```

Sind danach alle drei Gates gesetzt, den PR aus dem Draft holen: `gh pr ready <n>`. Sonst bleibt er Draft.

Nicht mergen, das macht der User.
