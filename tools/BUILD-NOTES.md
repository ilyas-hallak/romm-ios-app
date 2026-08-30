# Build Notes: PPSSPP (PSP) libretro-Core fuer romm-app

Grundlage fuer die spaetere GPL-Source-Offenlegung.
Dieser Core wird als eigenstaendige libretro-Dylib gebaut und zur Laufzeit per dlopen() in romm-app geladen.
Er ist unveraendert bis auf die unten dokumentierten Patches.

## Architektur-Unterschied zu Cabinet

Cabinet linkt alle libretro-Cores statisch in ein App-Binary und braucht deshalb einen Symbol-Prefix-Trick (psp_retro_* via C-Wrapper und `ld -r -exported_symbols_list`), damit sich die gleichnamigen retro_*-Symbole der Cores nicht gegenseitig ueberschreiben.

romm-app laedt jeden Core zur Laufzeit per dlopen() mit RTLD_LOCAL als separate .dylib/.framework.
Jeder Core hat seinen eigenen Namespace, es gibt keine Symbol-Kollision, der Prefix-Trick entfaellt vollstaendig.
Die von CMake erzeugte `<core>_libretro.dylib` exportiert bereits die einfachen retro_*-Symbole, die romm-apps LibretroFrontend erwartet (identisch zum vorhandenen `pcsx_rearmed_libretro_ios.dylib`, das 25 einfache `_retro_*` exportiert).

Entfallene Cabinet-Bausteine (und warum):

- Der C-Wrapper (`psp_wrapper.c`) mit den `psp_retro_*` Forwardern: nur fuer Static-Link-Kollisionen noetig.
- Der `ld -r -exported_symbols_list` Merge-Schritt, das Einsammeln aller `*.o` und `*.a` aus dem Build-Baum, die LZMA-Doppelkopie-Behandlung: alles Folge des Static-Merge.
- Der manuelle ffmpeg-`ld -r`-Schritt: CMake linkt die vendored ffmpeg-Archive beim Bau der Shared Library bereits selbst ein.
- Der Cabinet-spezifische `_cabinetPvrQueueDepth` Export (temporaeres tvOS-Input-Lag-Instrument): nicht relevant.

## Ziel-Output (romm-app Konvention)

`Vendor/Libretro/`:

- `ppsspp_libretro_ios.dylib` + `ppsspp_libretro_ios.framework`
- `ppsspp_libretro_tvos.dylib` + `ppsspp_libretro_tvos.framework`

Single-Arch arm64, Plattform iOS bzw. tvOS (kein Simulator, keine Fat-Binaries).
Das entspricht den vorhandenen Cores. Die .framework ist nur ein Wrapper (Binary + Info.plist), passend zu `genesis_plus_gx_libretro_ios.framework`.

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
| `-DIOS_PLATFORM=OS` (iOS) / `TVOS` (tvOS) | build-time | Waehlt in der Toolchain den iOS- bzw. tvOS-Zweig. TVOS zeigt die ffmpeg-Suche auf `ffmpeg/tvos/arm64`, OS auf `ffmpeg/ios/universal`. Upstream unterstuetzt LIBRETRO+IOS namentlich. |
| `-DLIBRETRO=ON` | build-time | Baut den libretro-Core, nicht die PPSSPP-App. |
| `-DUSE_SYSTEM_FFMPEG=OFF` | build-time | Nutzt die vendored, vorgebauten statischen ffmpeg-Archive (avcodec/avformat/avutil/swresample/swscale). CMake linkt sie beim Bau der Shared Library selbst ein. |
| `-DUSE_DISCORD=OFF` | build-time | Kein Discord-RPC auf iOS/tvOS. |
| Runtime-Option `ppsspp_cpu_core = "IR interpreter"` | runtime | PPSSPP waehlt sein CPU-Backend zur Laufzeit ueber diese libretro-Option. Da iOS/tvOS App-Prozesse kein JIT haben (SYSPROP_CAN_JIT = false), muss romm-app diese Option auf den IR-Interpreter zwingen. "IR JIT" faellt auf einer non-JIT-Plattform ebenfalls auf den IR-Interpreter zurueck. Der ARM64-JIT-Backend wird zwar mitkompiliert, aber nie ausgefuehrt. Kein Compile-Flag noetig. |

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
| **cmake** | **FEHLT.** Nachinstallieren: `brew install cmake` (Homebrew unter /opt/homebrew ist vorhanden) |
| ninja | fehlt, aber nicht noetig (Skript nutzt "Unix Makefiles") |

Blocker fuer den tatsaechlichen Build: nur cmake. Alles andere ist da.

---

## Offene Risiken / Unsicherheiten

1. **cmake fehlt** - vor jedem Build `brew install cmake`. Das Skript prueft das und bricht sonst sauber ab.

2. **PPSSPP ffmpeg.** Der Build haengt an den vendored, vorgebauten statischen ffmpeg-Archiven unter `ffmpeg/ios/universal/lib` bzw. `ffmpeg/tvos/arm64/lib`. Diese liegen als Submodul/Prebuilt im PPSSPP-Repo. Falls die Archive nach dem Clone fehlen (Submodul nicht geholt, oder Prebuilts nicht enthalten), muss ffmpeg via `ffmpeg/ios-build.sh` (upstream) selbst gebaut werden. Das Skript warnt, wenn `libavcodec.a` fehlt. Fuer die GPL-Offenlegung ist ffmpeg (LGPL/GPL) separat zu behandeln: den ffmpeg-Commit/Version aus dem PPSSPP-Submodul dokumentieren.

3. **PPSSPP CPU-Core zur Laufzeit.** Wenn romm-app `ppsspp_cpu_core` NICHT auf den IR-Interpreter zwingt, versucht der Core je nach Default ggf. den JIT und schlaegt ohne Entitlement fehl. Das ist eine App-seitige Core-Options-Aufgabe, kein Build-Thema. Muss beim Integrieren in LibretroFrontend/Core-Options gesetzt werden.

4. **BIOS/System-Dateien.**
   - PSP (PPSSPP) braucht in der Regel kein BIOS.
   - Cabinet selbst buendelt keine BIOS-Dateien.

5. **PPSSPP-Commit-Pin fehlt.** Fuer saubere GPL-Reproduzierbarkeit sollte vor dem finalen Build ein konkreter PPSSPP-Commit gewaehlt und in `PPSSPP_COMMIT` sowie hier eingetragen werden.

6. **Deployment Target.** Das Skript setzt 13.0 (PPSSPP-Vorgabe aus Cabinet). Der vorhandene pcsx-Core hat minos 12.2. Falls romm-app ein hoeheres/niedrigeres Minimum verlangt, `DEPLOYMENT_TARGET` im Skript anpassen.

7. **Kein Build ausgefuehrt.** Dieses Skript ist reviewt und syntaxgeprueft (`sh -n`), aber NICHT durchlaufen (cmake fehlt, und ein voller Core-Build dauert). Der erste echte Lauf kann weitere CMake-Option-Anpassungen noetig machen (insbesondere falls upstream sich seit Cabinets Stand verschoben hat).

## Angewandte Patches (Zusammenfassung fuer die Offenlegung)

PPSSPP: keine Source-Patches. Interpreter-Wahl erfolgt zur Laufzeit ueber die libretro-Option `ppsspp_cpu_core`.
