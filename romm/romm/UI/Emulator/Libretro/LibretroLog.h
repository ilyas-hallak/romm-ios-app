#ifndef LibretroLog_h
#define LibretroLog_h

#include <stdbool.h>

/// RETRO_ENVIRONMENT_GET_LOG_INTERFACE (27).
///
/// Die libretro-Spec erlaubt es dem Frontend, dieses Kommando abzulehnen — die
/// Cores muessen ihren `log_cb` dann selbst gegen NULL pruefen. PPSSPP tut das
/// nicht: `libretro.cpp:115` legt `static retro_log_printf_t log_cb;` an (also
/// NULL) und `libretro.cpp:142` ruft ihn ungeprueft auf. Dieser Aufruf haengt am
/// `init_output_audio_buffer(2048)` in der LETZTEN Zeile von `retro_init`
/// (libretro.cpp:1279), d.h. ein abgelehntes GET_LOG_INTERFACE bringt den Core
/// zuverlaessig beim Laden um: Sprung auf Adresse 0 -> KERN_PROTECTION_FAILURE
/// -> SIGKILL durch den Codesigning-Monitor. Flycast und PCSX ReARMed ueberleben
/// dasselbe nur, weil sie `if (log_cb)` schreiben.
///
/// Deshalb beantworten wir das Kommando wie RetroArch: immer mit einem gueltigen
/// Funktionspointer.

#ifdef __cplusplus
extern "C" {
#endif

/// Traegt unseren Log-Printf in die `struct retro_log_callback *` ein, die der
/// Core hereinreicht. `data` ist bewusst `void *`, damit der Bridging-Header
/// libretro.h nicht nach Swift durchreichen muss.
///
/// In Swift nicht nachbaubar: `retro_log_printf_t` ist eine C-variadische
/// Funktion, und Swift kann keine solche implementieren.
///
/// Gibt false zurueck, wenn der Core keinen Puffer mitgibt.
bool libretroInstallLogInterface(void *data);

#ifdef __cplusplus
}
#endif

#endif /* LibretroLog_h */
