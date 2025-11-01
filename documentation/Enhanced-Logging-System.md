# Enhanced Logging System - Benutzerhandbuch

## Überblick

Das erweiterte Logging-System für RomM iOS App bietet ein vollständiges, konfigurierbares Logging mit In-App Log-Viewer.

### Hauptfunktionen

✅ **Enable/Disable Toggle** - Logging standardmäßig deaktiviert
✅ **Picker für Log-Levels** - Bessere UX als Segmented Control
✅ **Detail-Screens** - Für jede Kategorie und jedes Setting
✅ **In-App Log-Viewer** - Logs direkt auf dem Gerät einsehen
✅ **Suchfunktion** - Durch alle Logs suchen
✅ **Filter** - Nach Level und Kategorie filtern
✅ **Export** - Als Text oder JSON exportieren

## Wichtig: Standard-Einstellung

**Logging ist standardmäßig DEAKTIVIERT!**

Das bedeutet:
- Keine Logs werden gesammelt
- Kein Performance-Overhead
- Kein Speicherverbrauch für Logs
- Muss manuell aktiviert werden

## Zugriff auf Logging-Einstellungen

In den App-Settings:

```
Einstellungen → Logging-Konfiguration
```

## Funktionen im Detail

### 1. Master Toggle - Logging aktivieren/deaktivieren

**Position:** Ganz oben in den Logging-Einstellungen

- **AUS (Default):** Keine Logs werden gesammelt, kein Performance-Impact
- **AN:** Logs werden nach konfigurierten Levels gesammelt

**Wichtig:** Wenn deaktiviert, funktioniert der Log-Viewer nicht, da keine Logs gespeichert werden.

### 2. Globales Log-Level (mit Picker)

**Statt Segmented Control jetzt:**
- Tippe auf "Globales Level"
- Öffnet Detail-Screen mit Picker
- Alle 6 Levels mit Beschreibungen
- Visuelles Feedback (Checkmark bei ausgewähltem Level)

**Levels:**
- 🔍 **Debug** - Zeigt alle Log-Nachrichten
- ℹ️ **Info** - Zeigt Info und höher
- 📢 **Notice** - Zeigt bemerkenswerte Ereignisse und höher
- ⚠️ **Warning** - Zeigt nur Warnungen und höher
- ❌ **Error** - Zeigt nur Fehler und Critical
- 💥 **Critical** - Zeigt nur kritische Meldungen

### 3. Kategorie-spezifische Einstellungen

**Jede Kategorie hat einen eigenen Detail-Screen:**

Verfügbare Kategorien:
- 🌐 **Network** - API-Aufrufe, HTTP-Requests
- 🎨 **UI** - View-Updates, User-Interaktionen
- 🗃️ **Data** - Repository, Daten-Caching
- 🔐 **Auth** - Login, Authentifizierung
- ⚡ **Performance** - Timing-Messungen
- 📦 **General** - Business-Logik, Use Cases
- 📚 **Manual** - PDF-Manual System
- 🔄 **ViewModel** - State-Management

**Für jede Kategorie:**
- Emoji-Icon
- Beschreibung was geloggt wird
- Eigenes Log-Level (Picker)
- Überschreibt globales Level wenn höher

### 4. Display-Optionen

**Toggles:**
- **Performance-Logs anzeigen** - Timing-Informationen ein/aus
- **Zeitstempel anzeigen** - Format: HH:mm:ss.SSS
- **Quellenangabe anzeigen** - Dateiname:Zeile

### 5. Log-Viewer (Neues Feature!)

**Zugriff:** In Logging-Einstellungen → "Log-Viewer öffnen"

#### Features:

**Suchfunktion:**
- Suchleiste oben
- Durchsucht Message, Dateiname, Funktion
- Echtzeit-Filterung

**Filter:**
- Nach Log-Level filtern (mehrere auswählbar)
- Nach Kategorie filtern (mehrere auswählbar)
- Kombinierbar mit Suche

**Anzeige:**
- Zeitstempel (HH:mm:ss.SSS)
- Level-Emoji + Kategorie-Emoji
- Message
- Expandable Details (Datei, Funktion, Zeile)
- Farbcodierung nach Level

**Statistiken:**
- Logs gesamt
- Gefilterte Anzahl
- Aktive Filter-Emojis

**Aktionen:**
- **Filter** - Öffnet Filter-Screen
- **Exportieren** - Als Text oder JSON
- **Alle löschen** - Löscht alle Logs

#### Log-Viewer Bedienung:

1. **Suchen:**
   - Suchleiste verwenden
   - Findet Text in Message, Datei, Funktion

2. **Filtern:**
   - Menü (⋯) → Filter
   - Log-Levels auswählen/abwählen
   - Kategorien auswählen/abwählen
   - "Alle auswählen" / "Keine auswählen"

3. **Details anzeigen:**
   - Wenn "Quellenangabe anzeigen" aktiviert
   - Tap auf Chevron (▼) bei jedem Log
   - Zeigt Datei, Funktion, Zeile, Kategorie, Level

4. **Exportieren:**
   - Menü (⋯) → Exportieren
   - **Als Text:** .txt Datei, menschenlesbar
   - **Als JSON:** .json Datei, maschinenlesbar
   - Share-Sheet öffnet sich automatisch

5. **Löschen:**
   - Menü (⋯) → Alle Logs löschen
   - Löscht alle gespeicherten Logs
   - Neue Logs werden weiter gesammelt

### 6. Reset-Funktion

**Button:** "Auf Standard zurücksetzen" (rot)

Setzt zurück auf:
- Logging: **DEAKTIVIERT**
- Globales Level: Debug
- Alle Kategorien: Debug
- Performance-Logs: AN
- Zeitstempel: AN
- Quellenangabe: AN

## Verwendungsszenarien

### Normal-Betrieb (Empfohlen)

```
Logging: AUS
```
- Keine Logs, keine Performance-Auswirkung
- Aktivieren nur bei Problemen

### Debugging vor Ort

```
Logging: AN
Globales Level: Debug
Alle Kategorien: Debug
Log-Viewer öffnen
```
- Alles wird geloggt
- Sofort in App ansehen
- Bei Fehler exportieren und an Support senden

### Netzwerk-Probleme debuggen

```
Logging: AN
Network: Debug
Auth: Debug
UI: Error
Data: Error
```
- Fokus auf Netzwerk und Auth
- Weniger Rauschen von UI/Data

### Performance-Analyse

```
Logging: AN
Performance-Logs: AN
Performance: Debug
Alle anderen: Error
```
- Nur Performance-Metriken
- Minimales Logging-Overhead

## Maximale Log-Anzahl

- **Maximum:** 10.000 Logs
- **Verhalten:** Älteste werden automatisch entfernt
- **Empfehlung:** Bei längeren Debugging-Sessions regelmäßig exportieren

## Performance-Tipps

1. **Deaktivieren wenn nicht benötigt**
   - Logging AUS = kein Overhead

2. **Höheres Level in Produktion**
   - Warning/Error statt Debug
   - Weniger Logs = bessere Performance

3. **Kategorien gezielt aktivieren**
   - Nur benötigte auf Debug
   - Rest auf Error

4. **Performance-Logs gezielt nutzen**
   - Nur aktivieren für Performance-Analysen
   - Sonst ausschalten

## Troubleshooting

### Keine Logs im Viewer

**Problem:** Log-Viewer ist leer

**Lösung:**
1. Ist Logging aktiviert?
2. Ist das Level richtig gesetzt?
3. Erzeugt die App überhaupt Logs?

### Zu viele Logs

**Problem:** Log-Viewer überflutet

**Lösung:**
1. Globales Level erhöhen (Info/Warning)
2. Kategorien einschränken
3. Filter verwenden
4. Suchfunktion nutzen

### Performance-Probleme

**Problem:** App läuft langsamer

**Lösung:**
1. Logging deaktivieren
2. Höheres Level setzen (Warning/Error)
3. Performance-Logs deaktivieren
4. Source-Location deaktivieren

### Export funktioniert nicht

**Problem:** Share-Sheet zeigt keine Apps

**Lösung:**
1. iOS System-Share-Sheet Problem
2. In Dateien-App speichern
3. Per AirDrop senden
4. Als JSON statt Text versuchen

## Export-Formate

### Text-Export (.txt)

**Format:** Menschenlesbar
```
[14:32:15.123] 🌐 [Network] [APIClient.swift:94] makeRequest - GET /api/roms - Status: 200
[14:32:15.125] ℹ️ [ViewModel] [RomViewModel.swift:49] loadRoms - Loaded 150 ROMs
```

**Verwendung:**
- Lesbar in jedem Text-Editor
- Gut für Support-Tickets
- Einfach zu teilen

### JSON-Export (.json)

**Format:** Strukturiert, maschinenlesbar
```json
[
  {
    "id": "UUID",
    "timestamp": "2025-11-01T14:32:15Z",
    "level": "info",
    "category": "network",
    "message": "GET /api/roms - Status: 200",
    "file": "APIClient.swift",
    "function": "makeRequest",
    "line": 94
  }
]
```

**Verwendung:**
- Automatische Analyse
- Import in Analyse-Tools
- Programmatische Verarbeitung

## FAQ

**Q: Warum ist Logging standardmäßig aus?**
A: Performance und Speicher. Nur aktivieren wenn benötigt.

**Q: Werden Logs auch bei deaktiviertem Logging ins System geschrieben?**
A: Nein. Wenn deaktiviert, wird GAR NICHTS geloggt.

**Q: Kann ich Logs über mehrere App-Starts behalten?**
A: Nein, Logs sind im Speicher. Bei App-Neustart sind sie weg. Vorher exportieren!

**Q: Wie viel Speicher verwenden die Logs?**
A: Max. 10.000 Logs, je nach Länge ca. 2-5 MB.

**Q: Kann ich Logs automatisch exportieren?**
A: Aktuell nein, nur manuell. Feature für zukünftige Version geplant.

**Q: Werden sensitive Daten geloggt?**
A: Nein, das System loggt keine Passwörter oder Tokens. Das ist in der App-Implementierung sichergestellt.

---

**Version:** 2.0
**Letzte Aktualisierung:** November 2025
**Neue Features:** Log-Viewer, Suchfunktion, Export, Picker-basierte Settings
