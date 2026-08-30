#ifndef LibretroHWRender_h
#define LibretroHWRender_h

#include <stdbool.h>
#include <stdint.h>

/// HW-Render-Pfad: eine schlanke C-API um Apples EAGL/OpenGLES3 herum.
///
/// Meilenstein 1 (unten: hwRenderMakeContext / hwRenderSetupFramebuffer /
/// hwRenderClearAndReadback) beweist Kontext + FBO + glReadPixels + Y-Flip
/// isoliert, ohne dass ein libretro-Core beteiligt ist.
///
/// Meilenstein 2 verdrahtet den echten SET_HW_RENDER-Vertrag: der Core rendert
/// in unser FBO, wir lesen es pro Frame zurueck und schicken es durch die
/// bestehende Software-Blit-Pipeline.
///
/// Threading: der Aufrufer muss ALLES (Kontexterzeugung, context_reset,
/// retro_run, Readback) auf demselben Thread fahren -- ein EAGL-Kontext ist an
/// den Thread gebunden, auf dem er current gemacht wurde. Im Frontend ist das
/// der Main-Thread, den der CADisplayLink treibt.

#ifdef __cplusplus
extern "C" {
#endif

/// Erzeugt (einmalig) einen EAGL-Kontext mit kEAGLRenderingAPIOpenGLES3 und
/// macht ihn current. Idempotent: ein bereits vorhandener Kontext wird nur
/// erneut current gemacht. Gibt false zurueck, wenn das Geraet/der Simulator
/// keinen GLES3-Kontext liefert.
bool hwRenderMakeContext(void);

/// (Re)erzeugt das Offscreen-FBO in der gewuenschten Geometrie. Color-Attachment
/// ist eine echte GL_TEXTURE_2D mit RGBA8. Depth/Stencil werden fuer M1 bewusst
/// weggelassen. Erfordert einen zuvor via hwRenderMakeContext erzeugten Kontext.
void hwRenderSetupFramebuffer(int width, int height);

/// Bindet das FBO, fuellt es rot (glClearColor(1,0,0,1)), liest es per
/// glReadPixels als GL_RGBA/GL_UNSIGNED_BYTE (GL_PACK_ALIGNMENT=1) zurueck und
/// schreibt es zeilenweise gespiegelt nach outRGBA, sodass die oberste
/// Bildzeile zuerst steht (top-left origin fuer den CGImage-Pfad).
///
/// outRGBA muss width*height*4 Bytes fassen. Gibt false bei fehlendem Kontext,
/// ungueltiger Geometrie oder unvollstaendigem FBO zurueck.
bool hwRenderClearAndReadback(uint8_t *outRGBA, int width, int height);

/// Gibt FBO, Textur und Kontext frei. Fuer M1 optional, aber sauber fuer Tests.
void hwRenderTeardown(void);

// --- libretro-Callbacks (ab Meilenstein 2 echt verdrahtet) ---

/// libretro get_current_framebuffer: liefert das FBO-Handle als uintptr_t.
uintptr_t hwRenderCurrentFramebuffer(void);

/// libretro get_proc_address: aufloesen von GL-Symbolen ueber den laufenden
/// Prozess (OpenGLES.framework ist statisch gelinkt).
void *hwRenderGetProcAddress(const char *symbol);

// --- Meilenstein 2: RETRO_ENVIRONMENT_SET_HW_RENDER (cmd 14) ---

/// Behandelt RETRO_ENVIRONMENT_SET_HW_RENDER. `data` ist ein
/// `struct retro_hw_render_callback *` — bewusst als void* deklariert, damit
/// dieser Header (und damit der Bridging-Header) libretro.h nicht nach Swift
/// durchreichen muss. Die echte struct wird ausschliesslich in der .mm gegen
/// die eingecheckte libretro.h gecastet, nie in Swift nachgebaut.
///
/// Akzeptiert GLES2 / GLES3 / GLES_VERSION. Es wird immer ein GLES3-Kontext
/// erzeugt (abwaertskompatibel zu GLES2-Cores). Alles andere -> false.
/// Traegt `get_current_framebuffer` und `get_proc_address` ein, merkt sich
/// context_reset / context_destroy / depth / stencil / bottom_left_origin.
bool hwRenderHandleSetHWRender(void *data);

/// True, sobald ein Core SET_HW_RENDER erfolgreich durchlaufen hat.
bool hwRenderIsActive(void);

/// Vom Core angefordertes Depth-Attachment (retro_hw_render_callback.depth).
bool hwRenderWantsDepth(void);

/// Vom Core angefordertes Stencil-Attachment (retro_hw_render_callback.stencil).
bool hwRenderWantsStencil(void);

/// true = Core rendert mit GL-Konvention (Ursprung unten-links), der Readback
/// muss dann zeilenweise spiegeln. false = libretro-Konvention (oben-links).
bool hwRenderBottomLeftOrigin(void);

/// Ruft den gespeicherten context_reset des Cores auf. Erst aufrufen, wenn
/// Kontext UND FBO stehen. No-op, wenn der Core keinen gesetzt hat.
void hwRenderInvokeContextReset(void);

/// Wie hwRenderSetupFramebuffer, zusaetzlich mit Depth- bzw. Packed-
/// Depth24/Stencil8-Renderbuffer. Flycast fordert depth=true an; ohne
/// Depth-Attachment scheitert jeder Blit. Idempotent: Neuaufbau nur bei
/// geaenderter Geometrie oder geaenderten Attachments.
void hwRenderSetupFramebufferEx(int width, int height, bool depth, bool stencil);

/// Liest das aktuelle FBO per glReadPixels (GL_RGBA/GL_UNSIGNED_BYTE) nach
/// `out` (width*height*4 Bytes). Y-Flip genau dann, wenn der Core
/// bottom_left_origin gesetzt hat, sodass beim Aufrufer immer die
/// Top-Left-Konvention der View ankommt.
bool hwRenderReadbackCurrentFBO(void *out, int width, int height);

#ifdef __cplusplus
}
#endif

#endif /* LibretroHWRender_h */
