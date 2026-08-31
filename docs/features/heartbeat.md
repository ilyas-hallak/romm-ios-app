
# Server-Version-Check (ROM Manager Companion App)

## Kontext / Problem
Das ROM-Manager-Backend veröffentlicht sehr häufig neue Versionen (wöchentlich / monatlich). Dabei ändern sich API-Verhalten und/oder Response-Strukturen teilweise kurzfristig. Das führt dazu, dass die Companion-App mit älteren Annahmen arbeitet und im Worst-Case crasht.

Ziel ist es, **die Server-Version zentral zu prüfen** und die App defensiv zu verhalten:
- **Beim Resume (Foreground):** einmalig prüfen und bei Änderungen den User ausloggen.
- **Beim Login:** prüfen, ob die Server-Version mit der App kompatibel ist (Konstante), ansonsten blockieren oder „auf eigene Faust“ erlauben.

---

## Ziele
1. **Crashes vermeiden**, indem inkompatible Server-/App-Kombinationen früh erkannt werden.
2. **Session-Konsistenz sicherstellen**, indem bei Server-Upgrades die aktuelle Session verworfen wird.
3. **Transparente UX**, indem User klare Hinweise erhalten und optional bewusst „auf eigenes Risiko“ fortfahren können.

---

## API Endpoint

curl -X 'GET' \
  'https://your-romm-server.example.com/api/heartbeat' \
  -H 'accept: application/json'

Response:
{
  "SYSTEM": {
    "VERSION": "4.5.0", // das benutzen
    "SHOW_SETUP_WIZARD": false
  },
  "METADATA_SOURCES": {
    "ANY_SOURCE_ENABLED": true,
    "IGDB_API_ENABLED": false,
    "SS_API_ENABLED": true,
    "MOBY_API_ENABLED": false,
    "STEAMGRIDDB_API_ENABLED": true,
    "RA_API_ENABLED": false,
    "LAUNCHBOX_API_ENABLED": false,
    "HASHEOUS_API_ENABLED": false,
    "PLAYMATCH_API_ENABLED": false,
    "TGDB_API_ENABLED": false,
    "FLASHPOINT_API_ENABLED": false,
    "HLTB_API_ENABLED": false
  },
  "FILESYSTEM": {
    "FS_PLATFORMS": []
  },
  "EMULATION": {
    "DISABLE_EMULATOR_JS": false,
    "DISABLE_RUFFLE_RS": false
  },
  "FRONTEND": {
    "UPLOAD_TIMEOUT": 600,
    "DISABLE_USERPASS_LOGIN": false,
    "YOUTUBE_BASE_URL": "https://www.youtube.com"
  },
  "OIDC": {
    "ENABLED": false,
    "PROVIDER": ""
  },
  "TASKS": {
    "ENABLE_SCHEDULED_RESCAN": false,
    "SCHEDULED_RESCAN_CRON": "0 3 * * *",
    "ENABLE_SCHEDULED_UPDATE_SWITCH_TITLEDB": false,
    "SCHEDULED_UPDATE_SWITCH_TITLEDB_CRON": "0 4 * * *",
    "ENABLE_SCHEDULED_UPDATE_LAUNCHBOX_METADATA": false,
    "SCHEDULED_UPDATE_LAUNCHBOX_METADATA_CRON": "0 4 * * *",
    "ENABLE_SCHEDULED_CONVERT_IMAGES_TO_WEBP": false,
    "SCHEDULED_CONVERT_IMAGES_TO_WEBP_CRON": "0 4 * * *"
  }
}

## App-Konstanten

In der App wird mindestens folgende Konstante definiert:

In der App wird mindestens folgende Konstante definiert:

MIN_SUPPORTED_SERVER_VERSION = "4.5.0" // beispielwert
MAX_TESTED_SERVER_VERSION = "4.2.0"

## Ablauf: Foreground-Check


Wenn die App in den Vordergrund kommt (Lifecycle Resume / Foreground Event).

Anforderungen
* Nur einmal pro Resume-Zyklus
* Kein mehrfacher paralleler Call
* Throttling (z. B. 30–60 Sekunden)


Ablauf
	1.	Wenn now - lastVersionCheckAt < THROTTLE_WINDOW → Abbrechen
	2.	serverVersion = fetchServerVersion()
	3.	Wenn lastKnownServerVersion != null
UND serverVersion != lastKnownServerVersion:
	•	Tokens löschen
	•	Session invalidieren
	•	User ausloggen
	•	UI-Hinweis anzeigen:
„Server wurde aktualisiert. Diese Version wird aktuell nicht unterstützt.“
	4.	lastKnownServerVersion = serverVersion
	5.	lastVersionCheckAt = now

Verhalten bei Netzwerkfehler
	•	Kein Logout
	•	Optional: stiller Fehler oder „Offline“-Hinweis

## Ablauf: Login-Check

Trigger

Beim Öffnen des Login-Screens oder unmittelbar vor dem Login-Versuch.

Ablauf
	1.	serverVersion = fetchServerVersion()
	2.	isCompatible = compare(serverVersion, MIN_SUPPORTED_SERVER_VERSION) >= 0
	3.	Wenn nicht kompatibel:
Login blockieren.
UI anzeigen:
Titel:
„Nicht kompatibel“
Text:
„Diese App-Version ist mit der Server-Version <serverVersion> nicht kompatibel.
Bitte aktualisiere die App oder nutze eine kompatible Server-Version.“
Optional:
	•	Button „Abbrechen“
	•	Button „Trotzdem fortfahren (auf eigene Faust)“
	4.	Wenn kompatibel oder Risiko akzeptiert:
	•	Normaler Login-Prozess


## Technische Architektur-Empfehlung

schaue hierzu nach CLAUDE.md an, hier wird die architektur beschrieben. halte dich auch wirklich daran, mit den layern use cases etc.

---

## Implementation Todo-Liste

### Phase 1: Domain Layer

- [ ] `Heartbeat.swift` - Domain Model erstellen (schlankes Wrapper um VERSION)
- [ ] `HeartbeatRepositoryProtocol.swift` - Repository Protocol erstellen
- [ ] `GetHeartbeatUseCase.swift` - Use Case für Heartbeat-Abruf

### Phase 2: Data Layer

- [ ] `RommAPIClient.swift` - Wrapper für `SystemAPI.heartbeatApiHeartbeatGet()` hinzufügen (existiert bereits!)
- [ ] `HeartbeatRepository.swift` - Repository Implementation erstellen

### Phase 3: DI Integration

- [ ] `DependencyFactory.swift` - Heartbeat Use Cases registrieren

### Phase 4: UI Layer - State & Logic

- [ ] `AppData.swift` - `lastKnownServerVersion` und `lastVersionCheckTime` hinzufügen
- [ ] `AppViewModel.swift` - Version-Check Logik mit Throttling implementieren
- [ ] Konstanten definieren: `MIN_SUPPORTED_SERVER_VERSION`, `VERSION_CHECK_THROTTLE_SECONDS`

### Phase 5: UI Layer - Views

- [ ] `AppView.swift` - ScenePhase Listener für Foreground-Check
- [ ] `SetupView.swift` - Login-Check mit Inkompatibilitäts-Dialog
- [ ] "Trotzdem fortfahren" Option implementieren

### Phase 6: Testing & Verifizierung

- [ ] Build erfolgreich
- [ ] Foreground-Check funktioniert (App Resume)
- [ ] Login-Check funktioniert (Inkompatibilitäts-Dialog)
- [ ] Throttling funktioniert (kein Spam)
- [ ] Version-Änderung löst Logout aus
