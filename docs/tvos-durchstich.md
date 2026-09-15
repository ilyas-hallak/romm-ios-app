# Apple TV (tvOS): Machbarkeit und Durchstich-Konzept

Stand: 15.08.2026. Erarbeitet auf Basis eines Code-Audits des Stands `main` @ `f8bd7a9`
(entspricht TestFlight Build 45). Reines Konzept, es wurde kein Code geändert.

## 1. Fragestellung

Kann die RomM-App auf Apple TV laufen, und wie sieht ein sinnvoller erster
Durchstich aus? Der Durchstich soll nicht die einfachen Features abdecken
(Login, Home, Collections funktionieren bereits), sondern den riskanten Teil:
**ROMs anschauen, laden und spielen**, mit Fokus auf **GBA** und **PSX**.

## 2. Ergebnis in drei Sätzen

Der Port ist machbar, und die RomM-App ist dafür strukturell besser geeignet
als jeder lokale Emulator. Es gibt weder ein Rechen-, ein Rechts- noch ein
Speicherproblem, die einzigen echten Kostenblöcke sind tvOS-Builds der
Libretro-Cores und eine zweite UI-Schale für die Focus Engine. Die zentrale
offene Entscheidung ist keine technische, sondern eine Produktfrage:
**Save-State-Kompatibilität zwischen iOS und tvOS** (siehe Abschnitt 9).

## 3. Der tvOS-Blocker, und warum er uns nicht trifft

tvOS gibt Apps **keinen persistenten Speicher**. Rund 500 KB in UserDefaults,
alles darüber landet in `Library/Caches` und wird vom System ohne Vorwarnung
gelöscht, wenn Platz knapp wird. Ein Documents-Verzeichnis mit
Persistenzgarantie existiert nicht, `applicationSupportDirectory` hilft dort
ebenfalls nicht. Bundle-Limit sind 4 GB, dazu bis 20 GB On-Demand Resources.

Für einen klassischen Emulator heisst das: ROMs, BIOS und Save States können
verschwinden. Deshalb gibt es kaum Emulatoren auf Apple TV. RetroArch führt
dazu ein offenes Issue, Provenance liefert CloudKit-Sync kostenlos und
standardmässig aktiviert aus, allein um Datenverlust zu verhindern.

**Für RomM ist das kein Problem, sondern der Heimvorteil.** Die Bibliothek
liegt ohnehin auf dem Server, ein Cache-Purge kostet nur einen erneuten
Download. Vorhanden sind bereits:

- `BIOSSyncUseCase` für BIOS-Dateien
- `CloudSaveSyncService` mit `pullBeforeLaunch()`, `pushBattery()`, `pushState()`
- Negotiated Sync über die RomM-Sync-API ab Server 4.9/5.0
- Device-Registrierung serverseitig

Provenance musste sich eine Cloud bauen, Riley Testut hat es gelassen, wir
haben sie schon.

Konsequenz für den Entwurf: **Save States müssen auf tvOS automatisch
hochladen.** Auf iOS ist Cloud-Sync Komfort, auf tvOS ist es die einzige
Datenhaltung.

## 4. Warum Delta nicht auf Apple TV ist

Relevant, weil es die These stützt.

Riley Testut hat die fehlende persistente Speicherung selbst als Hauptgrund
genannt, warum es keine Apple-TV-Version von Delta gibt. Deltas Modell ist eine
lokale Bibliothek, importiert über Files-App und iTunes File Sharing. Auf tvOS
gibt es weder Files-App noch Document Picker noch garantiert persistentes
Documents, damit fällt das gesamte Bibliotheksmodell auseinander.

Dazu die technische Seite, im vendorten Code gegengeprüft:

- `Vendor/DeltaCore/Package.swift:8-9` deklariert ausschliesslich `.iOS(.v14)`
- 24 von 60 Swift-Dateien in DeltaCore importieren UIKit
- Die Eingabeschicht ist vollständig touch-first: `ControllerView.swift` allein
  30 KB, dazu `TouchControllerSkin`, `TouchInputView`, `ThumbstickInputView`,
  `ImmediatePanGestureRecognizer`. Die `.deltaskin`-Bundles sind Bildkacheln mit
  Trefferflächen für Finger.

Deltas Blocker ist damit genau der, den wir nicht haben. Daraus folgt auch eine
Marktlücke: der bekannteste Emulator kommt aus strukturellen Gründen nicht auf
Apple TV, dort steht heute im Wesentlichen nur RetroArch.

## 5. Kein Rechen-, kein Rechtsproblem

**Hardware.** Apple TV 4K (3. Gen, 2022) hat einen A15 Bionic, 4 GB RAM, 64
oder 128 GB Flash. Derselbe Chip wie iPhone 13 Pro und iPhone 14, gleiche
arm64-Architektur. Am Netzteil, ohne Akku- und Thermalbudget, hält er seine
Taktraten sogar besser als ein iPhone. Für PS1, N64 oder DS ist das grosszügig.

**JIT.** Keiner der eingesetzten Cores braucht JIT. Damit ist der Code
AOT-kompiliertes C, und ein tvOS-Build ist ein Target-Wechsel, kein Rewrite.
JIT ist auf iOS ohnehin genauso gesperrt wie auf tvOS, es gibt also kein Delta
zwischen den Plattformen. Der N64-Dynarec ist entsprechend **kein**
tvOS-spezifisches Problem, was heute im App Store läuft, läuft dort auch.

**App Store.** Guideline 4.7 erlaubt Retro-Konsolen-Emulatoren seit April 2024,
RetroArch ist seit Mai 2024 im tvOS App Store. Nicht erlaubt bleiben Emulatoren,
die JIT brauchen (Dolphin, UTM), und aktuelle Konsolengenerationen.

**Von den 64 bzw. 128 GB gehört uns nichts verlässlich.** 4 GB Bundle plus
jederzeit löschbarer Cache. Für ein server-gestütztes Modell ist das egal, es
heisst aber: ohne erreichbaren Server startet nichts.

## 6. Architektur und Ordnerstruktur

### 6.1 Ausgangslage ist günstig

Aus dem Audit, 351 Swift-Dateien, ~41.700 Zeilen:

| Layer | Dateien | Zeilen | Anteil |
|---|---|---|---|
| Domain | 121 | 4.597 | 11 % |
| Data | 109 | 11.726 | 28 % |
| UI | 110 | 23.869 | 57 % |
| Services | 4 | 1.190 | 3 % |

Domain und Data sind zusammen nur 39 % und importieren fast nirgends UIKit. Die
Ausnahmen sind überschaubar:

- `Domain/Models/LocalDevice.swift:78-80` — `UIDevice.current.name/model/systemVersion`
- `Data/Repositories/SyncDeviceRepository.swift` — `UIDevice.current.name`
- `Data/Services/KingfisherCacheManager.swift` — `UIScreen.main.scale`
- `Data/Services/ConnectionLogger.swift` — `import SwiftUI`

Die Layer 1 und 2 der üblichen Multiplatform-Empfehlung (geteiltes Domain,
geteilte ViewModels) sind damit praktisch schon erreicht.

### 6.2 Zielstruktur

```
romm/romm/
  Domain/                  shared, unverändert
  Data/                    shared, unverändert
  UI/
    Shared/
      DI/                  DependencyFactory, plus tvOS-Zweig
      ViewModels/          die @Observable ViewModels wandern hierher
      Design/              Tokens, Farben, Typografie
      Components/          plattformfreie Bausteine
    iOS/                   heutige Views, 1:1 verschoben
    tvOS/                  neu
```

Der eigentliche Hebel ist, **ViewModels nach `UI/Shared/ViewModels/` zu ziehen**.
Sie liegen heute neben ihren Views. Für den Durchstich reicht es, die drei bis
vier zu ziehen, die der Slice braucht, nicht alle 110 Dateien anzufassen.

**Xcode.** Das Projekt nutzt `PBXFileSystemSynchronizedRootGroup` (5 Vorkommen in
`project.pbxproj`), neue Swift-Dateien werden also automatisch erfasst. Diese
Groups kennen Membership Exceptions pro Target: `UI/iOS` aus dem tvOS-Target
ausschliessen und umgekehrt. Kein manuelles Dateipflegen.

**Plattform-Weichen.** `#if os(tvOS)` nur auf Container-Ebene, nicht in jedem
Subview. Wo Verhalten abweicht, lieber ein Protokoll im Domain-Layer und zwei
Implementierungen, so wie es bei den Preferences schon gemacht wird.

### 6.3 Wichtige Korrektur: UIKit gibt es auf tvOS

`UIView`, `UIViewController`, `CALayer`, `CGImage`, Auto Layout, AVFoundation und
GameController sind auf tvOS vorhanden. Was fehlt, ist Touch und Gesten,
Orientation, `UIDocumentPicker`, `UIActivityViewController` und Haptics.

„UIKit-gekoppelt" ist also nicht gleichbedeutend mit „portiert nicht". Das ändert
den Zuschnitt erheblich, siehe nächster Abschnitt.

## 7. Portierbarkeit des Emulator-Stacks

| Datei | Zeilen | Imports | tvOS |
|---|---|---|---|
| `LibretroFrontend.swift` | 306 | Foundation, Darwin, AVFoundation | unverändert |
| `LibretroFrontend+Audio.swift` | 116 | Foundation, AVFoundation | unverändert |
| `LibretroFrontend+Environment.swift` | 127 | Foundation, Darwin | unverändert |
| `LibretroFrontend+SRAM.swift` | 35 | Foundation | unverändert |
| `LibretroABI.swift` | 123 | Foundation | unverändert |
| `LibretroVideoSink.swift` | 12 | Foundation | unverändert |
| `LibretroVideoView.swift` | 91 | UIKit, CoreGraphics | unverändert |
| `LibretroControllerInput.swift` | 159 | GameController | unverändert |
| `LibretroAspectRatio+UI.swift` | 21 | CoreGraphics | unverändert |
| `LibretroSession.swift` | 560 | UIKit, GameController | Touch, Pan-Geste, Orientation raus |
| `LibretroTouchControllerView.swift` | 494 | UIKit | entfällt |
| `LibretroEmulatorView.swift` | 392 | SwiftUI, UIKit | neu als tvOS-Shell |
| `LibretroEmulatorViewModel.swift` | 125 | Foundation, Observation, SwiftUI | nach Shared, leicht anpassen |

Von rund 2.560 Zeilen sind etwa 970 wortwörtlich übernehmbar, 560 leicht
anzupassen, der Rest fällt weg oder ist neu.

`LibretroVideoView` rendert per Software-Blit ein `CGImage` in
`CALayer.contents`, laut eigenem Kommentar als Zwischenlösung bis zu einer
Metal-Pipeline. Das läuft auf tvOS unverändert. Auf einem 4K-Panel skaliert die
GPU über `contentsGravity`, die `CGImage`-Erzeugung pro Frame bleibt aber
CPU-Arbeit. Für den Durchstich ausreichend, vor einem Release messen.

**Der Emulator ist damit der billigste Teil des Ports, nicht der teuerste.**

## 8. Der Durchstich

**Ziel in einem Satz:** Auf dem Apple TV einloggen, GBA- und PSX-ROMs sehen,
eines laden, starten, mit Controller spielen, Save State anlegen, zurück.

1. **Login.** Der Device-Authorization-Flow (`Services/DeviceAuthService.swift:56-208`)
   braucht auf dem Gerät selbst keinen Browser: der TV zeigt Code und
   Verification-URL, der Nutzer bestätigt am Handy, die App pollt. Genau der
   Flow, für den TVs gemacht sind. Nur eine Anzeige-View nötig.
2. **ROM-Liste.** Cover-Grid über die bestehenden UseCases. Auf der Focus Engine
   ist ein Grid das natürliche Layout.
3. **Download.** Bestehende Download-UseCases plus Fortschrittsanzeige.
4. **Spielen.** `LibretroSession` ohne Touch-Overlay, dazu
   `LibretroControllerInput` und `LibretroVideoView`.

Login, Home und Collections bleiben bewusst dünn, sie beweisen nichts Neues.

### 8.1 Controller-Input ist Voraussetzung, nicht Zubehör

Auf tvOS gibt es kein Touch, der Controller ist die einzige Eingabe. Die
Libretro-Controller-Bridge (PR #80, Branch `feature/libretro-controller-input`)
ist damit Grundvoraussetzung für den Port, nicht nur ein Bugfix. Sie muss auf
echter Hardware verifiziert sein, bevor Phase 3 sinnvoll ist.

Offen aus dem Review von PR #80: DeltaCore greift bei DualSense, Xbox und Switch
Pro den Home-Button ab und schaltet per `preferredSystemGestureState = .disabled`
die System-Geste weg (`Vendor/DeltaCore/DeltaCore/Game Controllers/MFi/MFiGameController.swift:284-290`).
Damit wird Menu für Start frei, ohne einen Spielbutton zu opfern. Der
Libretro-Pfad sollte das spiegeln, sonst verhalten sich beide Renderer bei
identischem Controller unterschiedlich.

## 9. Zentrale offene Entscheidung: Save States über Geräte hinweg

**Save States sind core-gebunden.** Ein Zustand ist ein Speicherabbild eines
konkreten Emulators. Nur Battery Saves (SRAM, `.sav`/`.srm`) sind
formatkompatibel, weil sie das abbilden, was die Cartridge selbst gespeichert
hätte.

Wenn tvOS libretro-only wird, iOS bei den nativen Plattformen aber auf DeltaCore
bleibt, heisst das: Save State am iPhone anlegen, vor den Fernseher setzen, Slot
ist sichtbar, lädt aber nicht. Battery Saves funktionieren, man landet am letzten
In-Game-Speicherpunkt. Betroffen wären GB, GBC, GBA, NES, SNES, N64, DS und
Mega Drive.

Für eine App, deren Alleinstellungsmerkmal die geräteübergreifende Bibliothek
ist, trifft das ausgerechnet den Pitch „weiterspielen auf dem grossen Bildschirm".

### 9.1 Delta vendort dieselben Emulatoren wie libretro

Aus den `.gitmodules` der Vendor-Submodule:

| Delta-Core | Upstream | libretro-Pendant | selber Emulator |
|---|---|---|---|
| GBADeltaCore | visualboyadvance-m | `vbam` bzw. `mgba` | nur bei `vbam` |
| GBCDeltaCore | gambatte | `gambatte` | ja |
| GPGXDeltaCore | Genesis-Plus-GX | `genesis_plus_gx` | ja |
| MelonDSDeltaCore | melonDS | `melonds` | ja |
| SNESDeltaCore | snes9x | `snes9x` | ja |
| N64DeltaCore | mupen64plus-core, GLideN64, mupen64plus-rsp-hle | `mupen64plus-next` | verwandt, anderer Fork |
| NESDeltaCore | kein Submodul, eingebettet | `nestopia` | offen |

Wichtig: Deltas GBA-Core ist **nicht** mGBA, sondern VBA-M. Für GBA auf tvOS
wäre daher `vbam_libretro` die bessere Wahl als `mgba_libretro`, obwohl mGBA der
modernere Emulator ist. Gleicher Upstream heisst reelle Chance auf
Kompatibilität, und die ist hier mehr wert als Emulator-Qualität.

### 9.2 Gleicher Emulator garantiert kein gleiches Format

Drei Gründe, warum das empirisch geprüft werden muss:

1. **Versionsstand.** Delta pinnt auf einen Commit, libretro auf einen anderen.
   Save-State-Formate sind versioniert und brechen über Versionsgrenzen.
2. **Anderer Einstiegspunkt.** Delta ruft die nativen Save-State-Funktionen,
   libretro geht über `retro_serialize`/`retro_unserialize`. Meist dieselbe
   Routine, aber Rahmung und Extdata können abweichen.
3. **Anderer Container.** Delta-Slots liegen als `.dltastate` und tragen ein
   Thumbnail mit (`readThumbnail`), sind also kein roher Core-Blob.

### 9.3 Das Experiment ist heute schon möglich

**Genesis Plus GX läuft im Repo bereits über beide Harnesses.** Mega Drive über
`GPGXDeltaCore` nativ, Master System, Game Gear, SG-1000 und Sega CD über
`genesis_plus_gx_libretro`. Derselbe Emulator, zwei Wrapper, beide installiert.

Test: einen Mega-Drive-Save-State über den nativen Pfad anlegen und im
libretro-Pfad zu laden versuchen.

- Klappt es, trägt die These auch für Gambatte, Snes9x und melonDS, und Weg C
  unten wird deutlich billiger.
- Klappt es nicht, ist die Frage erledigt und Weg A mit ehrlicher Kennzeichnung
  in der UI ist die realistische Variante.

### 9.4 Die drei Wege

**A, hinnehmen.** tvOS bekommt eigene Save States, Battery Saves synchronisieren.
Billigste Variante, muss dem Nutzer aber in der UI gesagt werden, sonst wirkt es
wie ein Bug. Der Sync müsste Slots nach Core taggen, sonst überschreiben sich
iPhone und TV gegenseitig unlesbare Zustände.

**B, GBA und PSX auch auf iOS zu libretro.** Nur die zwei Durchstich-Plattformen
umstellen, dann sind sie geräteübergreifend konsistent. Bestandsnutzer verlieren
ihre GBA-Slots, das bräuchte mindestens eine Warnung, besser eine Migration über
Battery Saves.

**C, langfristig libretro überall, DeltaCore raus.** Ein Renderer statt zwei, ein
Save-Format, eine Controller-Bridge, ein Core-Build-Prozess. Architektonisch die
sauberste Antwort, macht den tvOS-Port zum Nebeneffekt statt zum Sonderfall.
Grösste Einzelentscheidung im Projekt, und es kostet die Delta-Skins (Issue #68).

**Einschätzung:** C ist die Richtung, B der ehrliche erste Schritt. Der
Durchstich zwingt ohnehin dazu, einen GBA-Core für tvOS zu bauen. Existiert das
Framework, ist es fast geschenkt, es auch auf iOS zu laden und beide Plattformen
auf denselben Core zu stellen. Danach plattformweise nachziehen statt Big Bang.

## 10. Kritischer Pfad: die Cores

Der einzige echte Blocker.

**Bestand.** `Vendor/Libretro/` enthält drei Frameworks, alle arm64, alle
`platform=2` (iOS), `CFBundleSupportedPlatforms: iPhoneOS`, `MinimumOSVersion 12.2`:

- `pcsx_rearmed_libretro_ios.framework` (PlayStation)
- `mednafen_pce_fast_libretro_ios.framework` (PC Engine / TurboGrafx-16)
- `genesis_plus_gx_libretro_ios.framework` (Master System, Game Gear, SG-1000, Sega CD)

Geladen wird per `dlopen` aus `LibretroFrontend.swift`. Keine tvOS-Slices
vorhanden (tvOS wäre `platform=3`).

**Nötig für den Durchstich.**

- **PSX**: `pcsx_rearmed` als tvOS-Build.
- **GBA**: aktuell über DeltaCore, `PlatformSlugToGameType.swift:6` mappt `gba`
  auf `.gba`. Auf tvOS gibt es DeltaCore nicht. Also `vbam_libretro` (siehe 9.1)
  als tvOS-Build, GBA zusätzlich in `PlatformSlugToLibretroCore` aufnehmen und in
  `LaunchEmulatorUseCase` auf tvOS libretro gewinnen lassen. Auf iOS bleibt GBA
  bei DeltaCore, für Bestandsnutzer ändert sich damit nichts.

Ohne diese zwei Frameworks ist alles andere Trockenübung. Sollte Weg C verfolgt
werden, kommen später `gambatte`, `snes9x`, `nestopia`, `mupen64plus-next` und
`melonds` dazu, jeweils für iOS und tvOS.

Hinweis zur Verpackung: lose `.dylib` im `Frameworks/`-Ordner lösen bei der
App-Store-Abgabe ITMS-90426 aus. Cores müssen als `.framework` verpackt bleiben,
so wie es die bestehenden drei schon sind.

## 11. Phasenplan

| Phase | Inhalt | Abhängig von |
|---|---|---|
| 0 | tvOS-Slices für `pcsx_rearmed` und `vbam`, plus Entscheidung aus Abschnitt 9 | extern |
| 1 | tvOS-Target, Ordner-Split, App startet mit leerem Screen | nichts |
| 2 | Login, ROM-Liste, Download | Phase 1 |
| 3 | Emulator-Shell, Session ohne Touch | Phase 0 und 1 |
| 4 | Save States und Cloud-Sync verdrahten, Auto-Push | Phase 3 |

**Phase 1 ist unabhängig von den Cores** und die billige harte Antwort auf
„kompilieren Domain, Data und DI überhaupt für tvOS". Dort tauchen die
`UIDevice`- und Pfad-Themen auf.

## 12. Zwei Dinge, die von Anfang an richtig gemacht werden sollten

**Pfade zentralisieren.** Auf tvOS ist nur `Caches` beschreibbar. Für den
Durchstich egal, aber die Pfadbestimmung liegt heute verstreut:

- `Data/Services/DefaultFileSystemService.swift` (die vorhandene Abstraktion)
- `Data/Repositories/SaveStorePaths.swift:5-8` — direkter `.documentDirectory`
- `Data/Repositories/LocalROMRepository.swift:37` — direkter `.documentDirectory`
- `Domain/Models/LocalDevice.swift` — zweimal direkt
- `UI/Emulator/Libretro/LibretroSession.swift` — eigene private `documentsDirectory()`

Einmal hinter `DefaultFileSystemService` zusammenziehen, dann ist der tvOS-Zweig
eine Stelle statt fünf.

Aktuelles Layout:

```
Documents/Saves/{romId}/battery.sav
Documents/Saves/{romId}/states/{slot}.dltastate
Documents/ROMs/{Platform}/{ROM-Name}/
Documents/LibretroSystem/            (BIOS)
```

**Save States automatisch pushen.** Auf tvOS ist der Server die einzige
Datenhaltung, ein Purge löscht sonst kommentarlos den Spielstand.

## 13. Bewusst nicht im Scope

- DeltaCore auf tvOS portieren
- Web/EmulatorJS-Renderer, auf tvOS gibt es kein WKWebView. Ist über
  `AppFeatures.webEmulatorEnabled` (`Domain/Models/EmulatorEngine.swift:19-25`)
  bereits abschaltbar, Fallback auf `.native` existiert.
- Screen-Drag und Controller-Skins
- Haptics (`UIImpactFeedbackGenerator`, 4 Vorkommen)
- Share Sheet (`UIActivityViewController`, 6 Vorkommen)
- Collections und Suche, kommen nach dem Durchstich
- Analog-Sticks im Controller-Mapping

## 14. Aufwandseinschätzung

Zwei Audit-Agents kamen auf 15 bis 20 Stunden bzw. 2 bis 4 Wochen. Die
niedrigere Schätzung hat die Cores als „untouched" abgehakt, was nicht stimmt,
und die 23.869 Zeilen touch-first UI unterschätzt.

Realistisch **2 bis 4 Wochen**, dominiert von Core-Builds und der TV-UI, nicht
von Architekturarbeit. Phase 1 allein ist ein Tag.

## 15. Weitere Randbedingungen aus dem Audit

- `Info.plist` enthält iOS-spezifische Keys, die auf tvOS entfallen oder
  konditioniert werden müssen: `UIFileSharingEnabled`,
  `UISupportedInterfaceOrientations`, Scene Manifest, `NSCameraUsageDescription`.
  `NSAppTransportSecurity` und die `romm://`-URL-Schemes funktionieren auf tvOS.
- `romm.entitlements` enthält nur App-Sandbox und Read-Only-Dateizugriff, beides
  tvOS-tauglich.
- Test-Targets deklarieren bereits `xros`/`xrsimulator` und
  `XROS_DEPLOYMENT_TARGET 2.5`. Das ist visionOS, nicht tvOS, und im pbxproj gibt
  es null Treffer für `tvos`/`appletvos`.
- UserDefaults-Nutzung ist unkritisch klein, das 500-KB-Limit ist nicht in
  Gefahr. Einzig `SFTPRepository` legt einen JSON-Blob ab, den im Auge behalten.
- Orientation muss auf tvOS fix sein, betrifft `UI/App/Orientation/OrientationLock.swift`
  und `AppDelegate.swift:19-24`.
- SPM-Dependencies sind unkritisch: Kingfisher 8.5.0, SWCompression 4.9.1,
  BitByteData 2.1.0. ZIPFoundation deklariert selbst `.tvOS(.v9)`.
- Navigation nutzt `TabView` und `NavigationStack`, kein `NavigationSplitView`.
  Beides ist auf tvOS verfügbar.

## 16. Quellen

- [tvOS local storage: can the Documents folder be purged?](https://developer.apple.com/forums/thread/18465)
- [Apple TV hardware storage limits will keep most emulators away](https://appleinsider.com/articles/24/05/20/apple-tv-hardware-storage-limits-will-keep-most-emulators-away)
- [This tvOS restriction keeps game developers away from Apple TV](https://9to5mac.com/2024/05/20/tvos-restriction-game-apple-tv/)
- [RetroArch Issue #15885: tvOS auto copy ROMs and BIOS when tvOS cleans caches](https://github.com/libretro/RetroArch/issues/15885)
- [Provenance: Apple TV / tvOS Guide](https://wiki.provenance-emu.com/platforms-and-performance/tvos-guide)
- [Now Accepting Larger tvOS Binaries (4 GB)](https://developer.apple.com/news/?id=01122017c)
- [Delta Game Emulator Now Available From App Store](https://www.macrumors.com/2024/04/17/delta-game-emulator-iphone/)
- [Apple TV 4K (3rd generation) Tech Specs](https://support.apple.com/en-us/111839)
- [How to get into retro gaming on Apple TV with RetroArch](https://appleinsider.com/inside/apple-tv-4k/tips/how-to-get-into-retro-gaming-on-apple-tv-with-retroarch)
