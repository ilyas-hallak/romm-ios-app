# Build Notes: Flycast (Dreamcast) und PPSSPP (PSP) libretro-Cores fuer romm-app

Grundlage fuer die spaetere GPL-Source-Offenlegung.
Diese Cores werden als eigenstaendige libretro-Dylibs gebaut und zur Laufzeit per dlopen() in romm-app geladen.
Sie sind unveraendert bis auf die unten dokumentierten Patches.

## Architektur-Unterschied zu Cabinet

Cabinet linkt alle libretro-Cores statisch in ein App-Binary und braucht deshalb einen Symbol-Prefix-Trick (dc_retro_*, psp_retro_* via C-Wrapper und `ld -r -exported_symbols_list`), damit sich die gleichnamigen retro_*-Symbole der Cores nicht gegenseitig ueberschreiben.

romm-app laedt jeden Core zur Laufzeit per dlopen() mit RTLD_LOCAL als separate .dylib/.framework.
Jeder Core hat seinen eigenen Namespace, es gibt keine Symbol-Kollision, der Prefix-Trick entfaellt vollstaendig.
Die von CMake erzeugte `<core>_libretro.dylib` exportiert bereits die einfachen retro_*-Symbole, die romm-apps LibretroFrontend erwartet (identisch zum vorhandenen `pcsx_rearmed_libretro_ios.dylib`, das 25 einfache `_retro_*` exportiert).

Entfallene Cabinet-Bausteine (und warum):

- Der C-Wrapper (`dc_wrapper.c` / `psp_wrapper.c`) mit den `dc_retro_*` / `psp_retro_*` Forwardern: nur fuer Static-Link-Kollisionen noetig.
- Der `ld -r -exported_symbols_list` Merge-Schritt, das Einsammeln aller `*.o` und `*.a` aus dem Build-Baum, die LZMA-Doppelkopie-Behandlung: alles Folge des Static-Merge.
- Bei PPSSPP zusaetzlich der manuelle ffmpeg-`ld -r`-Schritt: CMake linkt die vendored ffmpeg-Archive beim Bau der Shared Library bereits selbst ein.
- Der Cabinet-spezifische `_cabinetPvrQueueDepth` Export (temporaeres tvOS-Input-Lag-Instrument): nicht relevant.

## Ziel-Output (romm-app Konvention)

`Vendor/Libretro/`:

- `flycast_libretro_ios.dylib` + `flycast_libretro_ios.framework`
- `flycast_libretro_tvos.dylib` + `flycast_libretro_tvos.framework`
- `ppsspp_libretro_ios.dylib` + `ppsspp_libretro_ios.framework`
- `ppsspp_libretro_tvos.dylib` + `ppsspp_libretro_tvos.framework`

Single-Arch arm64, Plattform iOS bzw. tvOS (kein Simulator, keine Fat-Binaries).
Das entspricht den vorhandenen Cores. Die .framework ist nur ein Wrapper (Binary + Info.plist), passend zu `genesis_plus_gx_libretro_ios.framework`.

---

## Flycast (Dreamcast)

- Upstream: https://github.com/flyinghead/flycast
- Verwendeter Commit: `a172e0001351` (aus Cabinet docs/licenses.md; im Skript als `FLYCAST_COMMIT` gepinnt, auf master umstellbar)
- Lizenz: GPL v2
- Build-System: CMake

### Essenzielle Bausteine

| Baustein | Typ | Warum noetig |
|---|---|---|
| `-DTARGET_NO_REC` | build-time | Erzwingt den SH4-Interpreter (kein Dynarec/JIT). iOS/tvOS App-Prozesse haben kein JIT-Entitlement. |
| `-DLIBRETRO=ON` | build-time | Baut nur den Core gegen die libretro-API, nicht Flycasts eigene App-Shell (Windowing/Input), die romm-app nie erreicht. |
| `-DCMAKE_SYSTEM_NAME=iOS`/`tvOS`, `-DCMAKE_OSX_SYSROOT`, `-DCMAKE_OSX_ARCHITECTURES=arm64`, `-DCMAKE_OSX_DEPLOYMENT_TARGET` | build-time | Cross-Compile fuer Device-arm64. |
| `-DUSE_OPENGL=ON` | build-time | GLES3-Renderpfad, den romm-app via RETRO_ENVIRONMENT_SET_HW_RENDER anfordert. |
| `-DUSE_VULKAN=ON` | build-time | Nur damit die CMake-Konfiguration durchlaeuft. Zur Laufzeit kostenlos, da GLES3 genutzt wird. |
| `-DIOS=ON` (nur tvOS) | build-time | tvOS muss sich gegenueber Flycasts GLES-Logik als iOS ausgeben. CMake setzt die `IOS`-Variable sonst nur fuer SYSTEM_NAME=iOS, nie fuer tvOS. Ohne sie faellt der tvOS-Build in den Desktop-GL-Zweig (GLES/HAVE_OPENGLES undefiniert, glsym.h zieht glsym_gl.h statt glsym_es3.h, Build bricht mit Desktop-GL-Typedef-Kollisionen ab). Bringt ausserdem TARGET_IPHONE mit, das core/types.h braucht, um den nur unter iOS verfuegbaren pthread_jit_write_protect_np-Zweig zu umgehen (harter Compile-Fehler auf tvOS sonst). Sicher, weil Interpreter-only. |
| Patch: `CPU_RATIO = 2` in `core/hw/sh4/sh4_interpreter.h` | build-time (Source-Patch) | Upstream lastet jede interpretierte Instruktion mit 8 Zyklen (effektiv ~25MHz SH4), was schwere Szenen einbrechen laesst. `2` gibt effektiv ~100MHz. Cabinet-Messung auf A15. Idempotent (sed matcht den aktuellen Integer). |
| Patch: `first_run = true;` in `retro_unload_game` (`shell/libretro/libretro.cpp`) | build-time (Source-Patch) | Flycast ruft `emu.start()` nur bei gesetztem `first_run`, und dieses Flag setzen nur retro_init/retro_deinit. romm-app deinitialisiert den dlopen'ten Core zwischen Spielen nicht, dadurch bliebe das zweite Spiel im State Loaded und zeigte einen schwarzen Screen. Der Patch setzt das Flag beim Entladen, damit das naechste Spiel wieder korrekt startet. Perl-Anker: die zweizeilige Oeffnung von retro_unload_game (`emu.unloadGame();` gefolgt von `dreampotato::term();`), idempotent. |

Patch-Anker verifiziert am 2026-08-29 gegen Commit `a172e0001351` und aktuellen master:

- `sh4_interpreter.h` enthaelt `static constexpr int CPU_RATIO = 8;` (Default) und `= 1;` (dynarec-Zweig). Der sed trifft beide auf 2 Setzungen. Achtung: der `= 1;` Zweig ist der `TARGET_NO_REC`-abhaengige, hier ggf. pruefen (siehe Risiken).
- `retro_unload_game()` (Zeile 2437 auf master) mit `emu.unloadGame();` (2440) direkt gefolgt von `dreampotato::term();` (2441). Anker gueltig.

### Build-Kommando (Kern)

```
cmake -S <src> -B <build> -G "Unix Makefiles" \
  -DCMAKE_SYSTEM_NAME=iOS \            # bzw. tvOS
  -DCMAKE_OSX_SYSROOT=iphoneos \       # bzw. appletvos
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBRETRO=ON -DUSE_OPENGL=ON -DUSE_VULKAN=ON \
  -DIOS=OFF \                          # ON fuer tvOS
  -DCMAKE_C_FLAGS="-fno-common -DTARGET_NO_REC -DIOS" \
  -DCMAKE_CXX_FLAGS="-fno-common -DTARGET_NO_REC -DIOS"
cmake --build <build> -j$(sysctl -n hw.ncpu)
```

Output: `<build>/.../flycast_libretro.dylib` -> umbenannt/kopiert nach `flycast_libretro_ios(.dylib|.framework)`.

---

## PPSSPP (PSP)

- Upstream: https://github.com/hrydgard/ppsspp
- Verwendeter Commit: kein Cabinet-Pin dokumentiert (PPSSPP war nicht Teil von Cabinets ausgeliefertem Core-Set). Default master. Zum Pinnen `PPSSPP_COMMIT` im Skript setzen und hier eintragen.
- Lizenz: GPL v2+
- Build-System: CMake mit eigener iOS/tvOS-Toolchain

### Essenzielle Bausteine

| Baustein | Typ | Warum noetig |
|---|---|---|
| `-DCMAKE_TOOLCHAIN_FILE=cmake/Toolchains/ios.cmake` | build-time | PPSSPPs eigene iOS/tvOS-Toolchain. Setzt USING_GLES2, MOBILE_DEVICE und richtet die ffmpeg-Suche plattformabhaengig aus. |
| `-DIOS_PLATFORM=OS` (iOS) / `TVOS` (tvOS) | build-time | Waehlt in der Toolchain den iOS- bzw. tvOS-Zweig. TVOS zeigt die ffmpeg-Suche auf `ffmpeg/tvos/arm64`, OS auf `ffmpeg/ios/universal`. Anders als bei Flycast keine Masquerade noetig, upstream unterstuetzt LIBRETRO+IOS namentlich. |
| `-DLIBRETRO=ON` | build-time | Baut den libretro-Core, nicht die PPSSPP-App. |
| `-DUSE_SYSTEM_FFMPEG=OFF` | build-time | Nutzt die vendored, vorgebauten statischen ffmpeg-Archive (avcodec/avformat/avutil/swresample/swscale). CMake linkt sie beim Bau der Shared Library selbst ein. |
| `-DUSE_DISCORD=OFF` | build-time | Kein Discord-RPC auf iOS/tvOS. |
| Runtime-Option `ppsspp_cpu_core = "IR interpreter"` | runtime | PPSSPP waehlt sein CPU-Backend zur Laufzeit ueber diese libretro-Option. Da iOS/tvOS App-Prozesse kein JIT haben (SYSPROP_CAN_JIT = false), muss romm-app diese Option auf den IR-Interpreter zwingen. "IR JIT" faellt auf einer non-JIT-Plattform ebenfalls auf den IR-Interpreter zurueck. Der ARM64-JIT-Backend wird zwar mitkompiliert, aber nie ausgefuehrt. Kein Compile-Flag noetig (anders als Flycasts TARGET_NO_REC). |

Verifiziert am 2026-08-29: `cmake/Toolchains/ios.cmake` existiert upstream und enthaelt `IOS_PLATFORM` (OS/SIMULATOR/TVOS), `set(MOBILE_DEVICE ON)`, `set(USING_GLES2 ON)` sowie die `IOS_PLATFORM STREQUAL "TVOS"` Zweige. Das `ffmpeg` Verzeichnis existiert im Repo (Submodul).

### Build-Kommando (Kern)

```
cmake -S <src> -B <build> -G "Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE=<src>/cmake/Toolchains/ios.cmake \
  -DIOS_PLATFORM=OS \                  # bzw. TVOS
  -DCMAKE_BUILD_TYPE=Release \
  -DLIBRETRO=ON -DUSE_SYSTEM_FFMPEG=OFF -DUSE_DISCORD=OFF \
  -DCMAKE_C_FLAGS=-fno-common -DCMAKE_CXX_FLAGS=-fno-common
cmake --build <build> -j$(sysctl -n hw.ncpu) --target ppsspp_libretro
```

Output: `<build>/.../ppsspp_libretro.dylib` -> umbenannt/kopiert nach `ppsspp_libretro_ios(.dylib|.framework)`.

---

## Toolchain-Status (geprueft 2026-08-29)

| Werkzeug | Status |
|---|---|
| xcodebuild | Xcode 26.6 (Build 17F113), vorhanden |
| iOS SDK | iPhoneOS26.5.sdk, vorhanden |
| tvOS SDK | AppleTVOS26.5.sdk, vorhanden |
| git | 2.50.1, vorhanden |
| perl | 5.34.1, vorhanden (fuer Flycast first_run-Patch) |
| **cmake** | **FEHLT.** Nachinstallieren: `brew install cmake` (Homebrew unter /opt/homebrew ist vorhanden) |
| ninja | fehlt, aber nicht noetig (Skripte nutzen "Unix Makefiles") |

Blocker fuer den tatsaechlichen Build: nur cmake. Alles andere ist da.

---

## Offene Risiken / Unsicherheiten

1. **cmake fehlt** - vor jedem Build `brew install cmake`. Die Skripte pruefen das und brechen sonst sauber ab.

2. **Flycast CPU_RATIO sed trifft zwei Stellen.** In der aktuellen `sh4_interpreter.h` gibt es `CPU_RATIO = 1` (dynarec-Zweig, per #if getrennt) und `CPU_RATIO = 8` (Interpreter-Default). Der sed aus Cabinet setzt jeden `CPU_RATIO = <int>` auf 2. Da wir mit `-DTARGET_NO_REC` nur den Interpreter bauen, ist nur der 8er-Wert relevant; den 1er auf 2 zu setzen ist im Interpreter-Build folgenlos. Bei Review kurz gegen den konkreten Checkout verifizieren.

3. **Flycast ANGLE / GLES.** Cabinet betreibt Flycast ueber GLES3, das die App selbst per RETRO_ENVIRONMENT_SET_HW_RENDER anfordert (LibretroFrontend stellt den GL-Kontext). romm-app muss denselben HW-Render-Kontext bereitstellen. Cabinets Perf-Arbeit lief teils gegen ANGLE (libGLESv2 Framework); ob romm-app das native iOS-GLES nutzt oder ebenfalls ANGLE braucht, ist offen und ausserhalb dieses Auftrags. `-DUSE_VULKAN=ON` ist nur ein Config-Zwang, kein Vulkan-Laufzeitpfad.

4. **PPSSPP ffmpeg.** Der Build haengt an den vendored, vorgebauten statischen ffmpeg-Archiven unter `ffmpeg/ios/universal/lib` bzw. `ffmpeg/tvos/arm64/lib`. Diese liegen als Submodul/Prebuilt im PPSSPP-Repo. Falls die Archive nach dem Clone fehlen (Submodul nicht geholt, oder Prebuilts nicht enthalten), muss ffmpeg via `ffmpeg/ios-build.sh` (upstream) selbst gebaut werden. Das Skript warnt, wenn `libavcodec.a` fehlt. Fuer die GPL-Offenlegung ist ffmpeg (LGPL/GPL) separat zu behandeln: den ffmpeg-Commit/Version aus dem PPSSPP-Submodul dokumentieren.

5. **PPSSPP CPU-Core zur Laufzeit.** Wenn romm-app `ppsspp_cpu_core` NICHT auf den IR-Interpreter zwingt, versucht der Core je nach Default ggf. den JIT und schlaegt ohne Entitlement fehl. Das ist eine App-seitige Core-Options-Aufgabe, kein Build-Thema. Muss beim Integrieren in LibretroFrontend/Core-Options gesetzt werden.

6. **BIOS/System-Dateien.**
   - Dreamcast (Flycast) braucht i.d.R. `dc_boot.bin` und `dc_flash.bin` im System-Verzeichnis (romm-app: `~/Documents/LibretroSystem/`), analog zu den PS1-BIOS-Dateien im README. Ohne BIOS bootet vieles nicht.
   - PSP (PPSSPP) braucht in der Regel kein BIOS.
   - Cabinet selbst buendelt keine BIOS-Dateien.

7. **PPSSPP-Commit-Pin fehlt.** Fuer saubere GPL-Reproduzierbarkeit sollte vor dem finalen Build ein konkreter PPSSPP-Commit gewaehlt und in `PPSSPP_COMMIT` sowie hier eingetragen werden. Flycast ist auf `a172e0001351` gepinnt.

8. **Deployment Target.** Skripte setzen 13.0 (PPSSPP-Vorgabe aus Cabinet). Der vorhandene pcsx-Core hat minos 12.2. Falls romm-app ein hoeheres/niedrigeres Minimum verlangt, `DEPLOYMENT_TARGET` in beiden Skripten anpassen.

9. **Kein Build ausgefuehrt.** Diese Skripte sind reviewt und syntaxgeprueft (`sh -n`), aber NICHT durchlaufen (cmake fehlt, und ein voller Core-Build dauert). Patch-Anker sind gegen Upstream verifiziert. Der erste echte Lauf kann weitere CMake-Option-Anpassungen noetig machen (insbesondere falls upstream sich seit Cabinets Stand verschoben hat).

## Angewandte Patches (Zusammenfassung fuer die Offenlegung)

Flycast (Commit a172e0001351), zwei Patches:

1. `core/hw/sh4/sh4_interpreter.h`: `CPU_RATIO` von 8 auf 2 (Interpreter-Underclock-Faktor).
2. `shell/libretro/libretro.cpp`: in `retro_unload_game()` nach `emu.unloadGame();` die Zeile `first_run = true;` eingefuegt.

PPSSPP: keine Source-Patches. Interpreter-Wahl erfolgt zur Laufzeit ueber die libretro-Option `ppsspp_cpu_core`.
