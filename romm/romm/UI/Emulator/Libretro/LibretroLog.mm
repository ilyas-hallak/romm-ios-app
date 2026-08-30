#import "LibretroLog.h"

// Wie in LibretroHWRender.mm: die echte libretro.h wird nur hier gecastet, nie
// in Swift nachgebaut.
#import "libretro.h"

#import <stdarg.h>
#import <stdio.h>
#import <string.h>

/// Der Funktionspointer, den der Core aufruft. Muss C-variadisch sein.
static void libretroLogPrintf(enum retro_log_level level, const char *fmt, ...)
{
    // RETRO_LOG_DEBUG ist bei PPSSPP sehr gespraechig (u.a. pro Audio-Puffer).
    // Im Release-Build kostet das nur Zeit, im Debug-Build wollen wir es sehen.
#ifndef DEBUG
    if (level == RETRO_LOG_DEBUG) { return; }
#endif

    if (fmt == NULL) { return; }

    char message[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(message, sizeof(message), fmt, args);
    va_end(args);

    const char *label = "?";
    switch (level) {
        case RETRO_LOG_DEBUG: label = "debug"; break;
        case RETRO_LOG_INFO:  label = "info";  break;
        case RETRO_LOG_WARN:  label = "warn";  break;
        case RETRO_LOG_ERROR: label = "error"; break;
        default: break;
    }

    // Die Cores haengen ihr eigenes "\n" an; wir ergaenzen es nur, wenn es fehlt,
    // damit die Zeilen im Konsolen-Log nicht verkleben.
    size_t length = strlen(message);
    const char *terminator = (length > 0 && message[length - 1] == '\n') ? "" : "\n";
    printf("[Core:%s] %s%s", label, message, terminator);
}

bool libretroInstallLogInterface(void *data)
{
    if (data == NULL) { return false; }
    ((struct retro_log_callback *)data)->log = libretroLogPrintf;
    return true;
}
