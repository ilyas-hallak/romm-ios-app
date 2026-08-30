#import "LibretroHWRender.h"

// Die echte libretro-Headerdatei, eingecheckt neben dieser Quelle (kopiert aus
// Flycasts deps/libretro-common). Bewusst NICHT in Swift nachgebaut: die drei
// einzelnen bools zwischen Funktionspointern in retro_hw_render_callback sind
// ein Padding-Minenfeld. Der Cast passiert ausschliesslich hier in ObjC++.
#import "libretro.h"

#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>

#import <dlfcn.h>
#import <vector>

// Prozess-globaler GL-Zustand. Es gibt genau einen Kontext und ein FBO.
// Kein Threading: alles laeuft (wie die Software-Pipeline) auf dem Main-Thread,
// getrieben vom CADisplayLink -- Kontexterzeugung, context_reset, retro_run und
// Readback also alle auf demselben Thread, auf dem der EAGL-Kontext current ist.
// Deshalb reicht einfacher globaler Zustand ohne Mutex.
static EAGLContext *gGLContext = nil;
static GLuint gFBO = 0;
static GLuint gColorTexture = 0;
static GLuint gDepthStencilRB = 0;
static GLint gFBOWidth = 0;
static GLint gFBOHeight = 0;
static bool gFBOHasDepth = false;
static bool gFBOHasStencil = false;

// Aus retro_hw_render_callback uebernommener Core-Zustand (SET_HW_RENDER).
static bool gHWRenderActive = false;
static bool gWantsDepth = false;
static bool gWantsStencil = false;
static bool gBottomLeftOrigin = false;
static retro_hw_context_reset_t gContextReset = nullptr;
static retro_hw_context_reset_t gContextDestroy = nullptr;

// Wiederverwendeter Zwischenpuffer fuer den gespiegelten Readback, damit pro
// Frame nichts alloziert wird.
static std::vector<uint8_t> gReadbackScratch;

bool hwRenderMakeContext(void) {
    // Apples EAGL/OpenGLES3, bewusst NICHT ANGLE. Jedes reale Zielgeraet dieser
    // App unterstuetzt GLES3; der Simulator ebenfalls.
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES3;
    if (gGLContext == nil || gGLContext.API != api) {
        gGLContext = [[EAGLContext alloc] initWithAPI:api];
    }
    if (gGLContext == nil) {
        NSLog(@"[HWRender] EAGLContext(GLES3) konnte nicht erzeugt werden");
        return false;
    }
    if (![EAGLContext setCurrentContext:gGLContext]) {
        NSLog(@"[HWRender] setCurrentContext fehlgeschlagen");
        return false;
    }
    NSLog(@"[HWRender] GLES3-Kontext current, GL_VERSION=%s GL_RENDERER=%s",
          glGetString(GL_VERSION), glGetString(GL_RENDERER));
    return true;
}

void hwRenderSetupFramebuffer(int width, int height) {
    // M1-Verhalten unveraendert: Color-only, kein Depth/Stencil.
    hwRenderSetupFramebufferEx(width, height, false, false);
}

void hwRenderSetupFramebufferEx(int width, int height, bool depth, bool stencil) {
    // Frueher still abgebrochen -- damit blieb gFBO 0, context_reset wurde
    // uebersprungen und der Core stuerzte erst viel spaeter beim ersten
    // GL-Zugriff ab. Der Fehlschlag muss an seiner Ursache sichtbar sein.
    if (gGLContext == nil) {
        NSLog(@"[HWRender] FBO-Setup abgebrochen: kein GL-Kontext");
        return;
    }
    if (width <= 0 || height <= 0) {
        NSLog(@"[HWRender] FBO-Setup abgebrochen: ungueltige Masse %dx%d", width, height);
        return;
    }
    [EAGLContext setCurrentContext:gGLContext];

    // Nur Depth allein oder Depth+Stencil sind gueltig. libretro.h: "Only
    // attaching stencil is invalid and will be ignored."
    if (stencil && !depth) {
        NSLog(@"[HWRender] stencil ohne depth angefordert -- ignoriert (libretro-Vertrag)");
        stencil = false;
    }

    if (gFBO != 0 && gFBOWidth == width && gFBOHeight == height &&
        gFBOHasDepth == depth && gFBOHasStencil == stencil) {
        return; // schon in der passenden Geometrie mit denselben Attachments
    }
    if (gFBO != 0) {
        glDeleteFramebuffers(1, &gFBO);
        gFBO = 0;
    }
    if (gColorTexture != 0) {
        glDeleteTextures(1, &gColorTexture);
        gColorTexture = 0;
    }
    if (gDepthStencilRB != 0) {
        glDeleteRenderbuffers(1, &gDepthStencilRB);
        gDepthStencilRB = 0;
    }

    glGenFramebuffers(1, &gFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, gFBO);

    // Color-Attachment als echte GL_TEXTURE_2D (RGBA8).
    glGenTextures(1, &gColorTexture);
    glBindTexture(GL_TEXTURE_2D, gColorTexture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, gColorTexture, 0);

    // Depth bzw. Packed Depth24/Stencil8. Flycast setzt depth=true; ohne
    // Depth-Attachment scheitert jeder Blit des Cores.
    if (depth) {
        glGenRenderbuffers(1, &gDepthStencilRB);
        glBindRenderbuffer(GL_RENDERBUFFER, gDepthStencilRB);
        if (stencil) {
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT,
                                      GL_RENDERBUFFER, gDepthStencilRB);
        } else {
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                      GL_RENDERBUFFER, gDepthStencilRB);
        }
        glBindRenderbuffer(GL_RENDERBUFFER, 0);
    }

    gFBOWidth = width;
    gFBOHeight = height;
    gFBOHasDepth = depth;
    gFBOHasStencil = stencil;

    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSLog(@"[HWRender] FBO %dx%d depth=%d stencil=%d status=0x%04X (%s)",
          width, height, depth ? 1 : 0, stencil ? 1 : 0, status,
          status == GL_FRAMEBUFFER_COMPLETE ? "complete" : "INCOMPLETE");
}

bool hwRenderClearAndReadback(uint8_t *outRGBA, int width, int height) {
    if (gGLContext == nil || outRGBA == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    [EAGLContext setCurrentContext:gGLContext];

    if (gFBO == 0 || gFBOWidth != width || gFBOHeight != height) {
        hwRenderSetupFramebuffer(width, height);
    }

    glBindFramebuffer(GL_FRAMEBUFFER, gFBO);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"[HWRender] readback abgebrochen: FBO unvollstaendig");
        return false;
    }

    glViewport(0, 0, width, height);

    // Y-Flip-/Orientierungs-Test (M1): asymmetrisches Muster statt einfarbig rot.
    // Ein einfarbiger Frame kann Orientierung nicht beweisen; dieses Muster schon.
    // In GL-Koordinaten gezeichnet (Ursprung unten-links). Der Readback unten
    // spiegelt die Zeilen, sodass GL-oben zu Bild-oben wird. Erwartetes
    // Display-Bild nach korrektem Y-Flip:
    //   - obere Haelfte ROT, untere Haelfte BLAU
    //   - kleines GRUENES Quadrat in der oberen LINKEN Ecke
    // Abweichungen zeigen den Fehler sofort:
    //   blau oben         -> vertikaler Flip falsch
    //   gruen oben-rechts -> horizontal gespiegelt
    //   gruen unten-links -> vertikaler Flip falsch
    const GLint half = height / 2;
    const GLint marker = (width < height ? width : height) / 6;

    // 1) Ganzes FBO blau.
    glDisable(GL_SCISSOR_TEST);
    glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // 2) Obere GL-Haelfte rot (GL-oben == Bild-oben nach Flip).
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, half, width, height - half);
    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    // 3) Gruener Marker in GL-oben-links == Bild-oben-links.
    glScissor(0, height - marker, marker, marker);
    glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glDisable(GL_SCISSOR_TEST);

    // Vorhandene Fehler leeren, damit ein Fehler nach dem Readback wirklich vom
    // Readback stammt (glGetError liefert einen Fehler pro Aufruf in Reihenfolge).
    while (glGetError() != GL_NO_ERROR) { /* drain */ }

    const size_t bytesPerRow = (size_t)width * 4;
    const size_t total = bytesPerRow * (size_t)height;

    // GL_RGBA/GL_UNSIGNED_BYTE ist die einzige von jeder GLES3-Implementierung
    // garantiert akzeptierte Format/Typ-Kombination fuer glReadPixels.
    // GL_PACK_ALIGNMENT=1, damit Zeilen ohne Padding gepackt werden.
    glPixelStorei(GL_PACK_ALIGNMENT, 1);

    // In einen temporaeren Puffer lesen (GL-Origin unten-links), danach
    // zeilenweise gespiegelt nach outRGBA schreiben, sodass Zeile 0 oben liegt.
    std::vector<uint8_t> scratch(total);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, scratch.data());

    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        NSLog(@"[HWRender] glReadPixels error=0x%04X", err);
        return false;
    }

    for (int y = 0; y < height; ++y) {
        const uint8_t *src = scratch.data() + (size_t)(height - 1 - y) * bytesPerRow;
        uint8_t *dst = outRGBA + (size_t)y * bytesPerRow;
        memcpy(dst, src, bytesPerRow);
    }

    // Selbstdiagnose der vier Ecken im fertig gespiegelten Bild (Origin oben-links).
    // Erwartet: TL gruen [0,255,0], TR rot [255,0,0], BL/BR blau [0,0,255].
    const uint8_t *tl = outRGBA;
    const uint8_t *tr = outRGBA + (size_t)(width - 1) * 4;
    const uint8_t *bl = outRGBA + (size_t)(height - 1) * bytesPerRow;
    const uint8_t *br = outRGBA + (size_t)(height - 1) * bytesPerRow + (size_t)(width - 1) * 4;
    NSLog(@"[HWRender] pattern %dx%d  TL=[%u,%u,%u] TR=[%u,%u,%u] BL=[%u,%u,%u] BR=[%u,%u,%u]",
          width, height,
          tl[0], tl[1], tl[2], tr[0], tr[1], tr[2],
          bl[0], bl[1], bl[2], br[0], br[1], br[2]);
    return true;
}

void hwRenderTeardown(void) {
    if (gGLContext) {
        [EAGLContext setCurrentContext:gGLContext];
    }
    if (gFBO != 0) { glDeleteFramebuffers(1, &gFBO); gFBO = 0; }
    if (gColorTexture != 0) { glDeleteTextures(1, &gColorTexture); gColorTexture = 0; }
    if (gDepthStencilRB != 0) { glDeleteRenderbuffers(1, &gDepthStencilRB); gDepthStencilRB = 0; }
    gFBOWidth = 0;
    gFBOHeight = 0;
    gFBOHasDepth = false;
    gFBOHasStencil = false;
    // Core-Zustand mitloeschen: die Funktionspointer zeigen in die Core-Dylib,
    // die der Frontend-Stop gleich dlclose't. context_destroy wird hier bewusst
    // NICHT gerufen -- Teardown kann nach dem dlclose laufen, und der Sprung in
    // ein entladenes Textsegment waere ein sicherer Crash.
    gHWRenderActive = false;
    gWantsDepth = false;
    gWantsStencil = false;
    gBottomLeftOrigin = false;
    gContextReset = nullptr;
    gContextDestroy = nullptr;
    gReadbackScratch.clear();
    gReadbackScratch.shrink_to_fit();
    [EAGLContext setCurrentContext:nil];
    gGLContext = nil;
}

// --- libretro-Callbacks ---

uintptr_t hwRenderCurrentFramebuffer(void) {
    return (uintptr_t)gFBO;
}

void *hwRenderGetProcAddress(const char *symbol) {
    if (symbol == nullptr) { return nullptr; }
    // OpenGLES.framework ist statisch gelinkt, deshalb loest ein einfaches
    // dlsym gegen den laufenden Prozess die Standard-GL-Entry-Points auf.
    return dlsym(RTLD_DEFAULT, symbol);
}

/// Signatur-Adapter: libretro erwartet retro_proc_address_t (void(*)(void)),
/// unsere C-API liefert void*. Der Cast ist hier gebuendelt statt im Header.
static retro_proc_address_t hwRenderProcAddressThunk(const char *symbol) {
    return (retro_proc_address_t)hwRenderGetProcAddress(symbol);
}

// --- Meilenstein 2: RETRO_ENVIRONMENT_SET_HW_RENDER ---

bool hwRenderHandleSetHWRender(void *data) {
    if (data == nullptr) {
        NSLog(@"[HWRender] SET_HW_RENDER ohne data");
        return false;
    }
    struct retro_hw_render_callback *cb = (struct retro_hw_render_callback *)data;

    // Auf iOS gibt es nur EAGL/GLES. Ein GLES3-Kontext bedient auch GLES2-Cores,
    // deshalb wird jede der drei GLES-Varianten akzeptiert.
    switch (cb->context_type) {
        case RETRO_HW_CONTEXT_OPENGLES2:
        case RETRO_HW_CONTEXT_OPENGLES3:
        case RETRO_HW_CONTEXT_OPENGLES_VERSION:
            break;
        default:
            NSLog(@"[HWRender] SET_HW_RENDER abgelehnt: context_type=%u wird nicht unterstuetzt "
                  @"(nur GLES2=2 / GLES3=4 / GLES_VERSION=5)", (unsigned)cb->context_type);
            return false;
    }

    gContextReset = cb->context_reset;
    gContextDestroy = cb->context_destroy;
    gWantsDepth = cb->depth;
    gWantsStencil = cb->stencil;
    gBottomLeftOrigin = cb->bottom_left_origin;

    // Die einzigen beiden Felder, die das Frontend schreibt.
    cb->get_current_framebuffer = hwRenderCurrentFramebuffer;
    cb->get_proc_address = hwRenderProcAddressThunk;

    gHWRenderActive = true;

    NSLog(@"[HWRender] SET_HW_RENDER akzeptiert: context_type=%u version=%u.%u depth=%d "
          @"stencil=%d bottom_left_origin=%d cache_context=%d debug_context=%d "
          @"context_reset=%p context_destroy=%p",
          (unsigned)cb->context_type, cb->version_major, cb->version_minor,
          cb->depth ? 1 : 0, cb->stencil ? 1 : 0, cb->bottom_left_origin ? 1 : 0,
          cb->cache_context ? 1 : 0, cb->debug_context ? 1 : 0,
          (void *)cb->context_reset, (void *)cb->context_destroy);
    return true;
}

bool hwRenderIsActive(void) { return gHWRenderActive; }
bool hwRenderWantsDepth(void) { return gWantsDepth; }
bool hwRenderWantsStencil(void) { return gWantsStencil; }
bool hwRenderBottomLeftOrigin(void) { return gBottomLeftOrigin; }

void hwRenderInvokeContextReset(void) {
    if (gContextReset == nullptr) {
        NSLog(@"[HWRender] context_reset: Core hat keinen gesetzt, uebersprungen");
        return;
    }
    if (gGLContext == nil || gFBO == 0) {
        NSLog(@"[HWRender] context_reset uebersprungen: Kontext oder FBO fehlt");
        return;
    }
    // Muss auf dem Thread laufen, auf dem der Kontext current ist -- das ist
    // derselbe Main-Thread, der spaeter retro_run treibt.
    [EAGLContext setCurrentContext:gGLContext];
    glBindFramebuffer(GL_FRAMEBUFFER, gFBO);
    NSLog(@"[HWRender] context_reset -> Core");
    gContextReset();
    NSLog(@"[HWRender] context_reset zurueck");
}

bool hwRenderReadbackCurrentFBO(void *out, int width, int height) {
    if (gGLContext == nil || out == nullptr || width <= 0 || height <= 0) {
        return false;
    }
    [EAGLContext setCurrentContext:gGLContext];

    if (gFBO == 0) {
        NSLog(@"[HWRender] readback abgebrochen: kein FBO");
        return false;
    }

    // Der Core meldet pro Frame seine eigene Framebuffer-Geometrie und die muss
    // nicht der base_width/base_height aus retro_get_system_av_info entsprechen:
    // Flycast meldet dort fix 640x480, rendert aber in interner Aufloesung
    // (Default 853x480). Aus einem zu kleinen FBO zu lesen liefert undefinierte
    // Pixel, also lieber das FBO passend neu aufbauen und den Frame verwerfen --
    // ab dem naechsten Frame holt der Core sich per get_current_framebuffer das
    // neue Handle. Deckt auch eine Aufloesungsaenderung zur Laufzeit ab.
    if (gFBOWidth != width || gFBOHeight != height) {
        NSLog(@"[HWRender] Frame %dx%d passt nicht zum FBO %dx%d -- FBO wird neu aufgebaut, Frame verworfen",
              width, height, gFBOWidth, gFBOHeight);
        hwRenderSetupFramebufferEx(width, height, gWantsDepth, gWantsStencil);
        return false;
    }

    // Der Core laesst nach seinem Blit irgendein FBO gebunden zuruecken,
    // deshalb hier explizit auf unseres zurueck.
    glBindFramebuffer(GL_FRAMEBUFFER, gFBO);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"[HWRender] readback abgebrochen: FBO unvollstaendig");
        return false;
    }

    const size_t bytesPerRow = (size_t)width * 4;
    const size_t total = bytesPerRow * (size_t)height;

    while (glGetError() != GL_NO_ERROR) { /* drain */ }

    // GL_RGBA/GL_UNSIGNED_BYTE ist die einzige auf GLES garantierte
    // Format/Typ-Kombination fuer glReadPixels. GL_PACK_ALIGNMENT=1, damit
    // Zeilen ohne Padding gepackt werden.
    glPixelStorei(GL_PACK_ALIGNMENT, 1);

    uint8_t *dstBase = (uint8_t *)out;

    if (!gBottomLeftOrigin) {
        // Core rendert bereits in libretro-Konvention (oben-links) -- direkt
        // in den Zielpuffer lesen, kein Flip noetig.
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, dstBase);
    } else {
        // GL-Konvention (unten-links): ueber einen wiederverwendeten
        // Zwischenpuffer lesen und zeilenweise gespiegelt kopieren, sodass
        // Zeile 0 oben liegt.
        if (gReadbackScratch.size() < total) {
            gReadbackScratch.resize(total);
        }
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, gReadbackScratch.data());
    }

    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        NSLog(@"[HWRender] glReadPixels error=0x%04X", err);
        return false;
    }

    if (gBottomLeftOrigin) {
        for (int y = 0; y < height; ++y) {
            const uint8_t *src = gReadbackScratch.data() + (size_t)(height - 1 - y) * bytesPerRow;
            memcpy(dstBase + (size_t)y * bytesPerRow, src, bytesPerRow);
        }
    }
    return true;
}
