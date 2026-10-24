#include "RDPBridge.h"
#include <freerdp/client.h>
#include <freerdp/client/channels.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/client/disp.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/graphics.h>
#include <freerdp/codec/color.h>
#include <freerdp/input.h>
#include <freerdp/event.h>
#include <freerdp/error.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>
#include <Security/Security.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { rdpClientContext common; MRSession *owner; } MRContext;
typedef struct { uint64_t epoch; uint32_t key; uint16_t flags, x, y; bool down, repeat, pointer; } MRInput;
struct MRSession {
    rdpContext *context;
    MRCallbacks callbacks;
    void *user;
    HANDLE wake;
    pthread_mutex_t input_lock, frame_lock, certificate_lock, display_lock;
    pthread_cond_t certificate_condition;
    atomic_bool stop, connected;
    atomic_uint error;
    bool input_enabled, cleanup, certificate_waiting, certificate_accepted;
    MRInput input[1024];
    size_t head, count;
    uint64_t input_epoch, display_max_area;
    bool keys[512];
    uint16_t buttons;
    uint16_t pointer_x, pointer_y;
    uint32_t requested_width, requested_height, requested_scale;
    bool resize_pending, display_ready;
    bool synchronize_pending;
    uint32_t toggles;
    DispClientContext *display;
    uint8_t *frame;
    size_t frame_capacity, frame_size;
    uint64_t frame_copied_bytes;
    uint32_t width, height, stride;
    char *fingerprint;
};
static pthread_once_t logging_once = PTHREAD_ONCE_INIT;
static void quiet_logging(void) { WLog_SetLogLevel(WLog_GetRoot(), WLOG_OFF); }

static MRSession *owner(rdpContext *context) { return ((MRContext *)context)->owner; }
static void state(MRSession *s, int value, uint32_t error) {
    atomic_store(&s->error, error);
    if (s->callbacks.state) s->callbacks.state(s->user, value, error);
}
static BOOL authenticate(freerdp *instance, char **u, char **p, char **d, rdp_auth_reason reason) {
    (void)instance; (void)u; (void)p; (void)d; (void)reason;
    return false;
}
static int verify_certificate(freerdp *instance, const BYTE *data, size_t length,
                              const char *host, UINT16 port, DWORD flags) {
    (void)port; (void)flags;
    MRSession *s = owner(instance->context);
    char *pem = calloc(length + 1, 1);
    if (!pem) return 0;
    memcpy(pem, data, length);
    rdpCertificate *certificate = freerdp_certificate_new_from_pem(pem);
    if (!certificate) { free(pem); return 0; }
    char *fingerprint = freerdp_certificate_get_fingerprint_by_hash(certificate, "sha256");
    char *subject = freerdp_certificate_get_subject(certificate);
    char *issuer = freerdp_certificate_get_issuer(certificate);
    bool pinned = s->fingerprint && *s->fingerprint;
    int result = 0;
    if (!fingerprint) goto end;
    if (pinned && strcmp(s->fingerprint, fingerprint) == 0) { result = 2; goto end; }
    CFMutableArrayRef chain = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (!chain) goto end;
    for (char *start = pem; start && *start;) {
        start = strstr(start, "-----BEGIN CERTIFICATE-----");
        if (!start) break;
        char *finish = strstr(start, "-----END CERTIFICATE-----");
        if (!finish) break;
        finish += strlen("-----END CERTIFICATE-----");
        char saved = *finish; *finish = 0;
        rdpCertificate *part = freerdp_certificate_new_from_pem(start);
        *finish = saved;
        if (part) {
            size_t size = 0;
            BYTE *der = freerdp_certificate_get_der(part, &size);
            if (der) {
                CFDataRef bytes = CFDataCreate(NULL, der, (CFIndex)size);
                SecCertificateRef item = bytes ? SecCertificateCreateWithData(NULL, bytes) : NULL;
                if (item) { CFArrayAppendValue(chain, item); CFRelease(item); }
                if (bytes) CFRelease(bytes);
                free(der);
            }
            freerdp_certificate_free(part);
        }
        start = finish;
    }
    CFStringRef name = CFStringCreateWithCString(NULL, host, kCFStringEncodingUTF8);
    if (!name) { CFRelease(chain); goto end; }
    SecPolicyRef policy = SecPolicyCreateSSL(true, name);
    if (!policy) { CFRelease(name); CFRelease(chain); goto end; }
    SecTrustRef trust = NULL;
    bool trusted = SecTrustCreateWithCertificates(chain, policy, &trust) == errSecSuccess
        && SecTrustEvaluateWithError(trust, NULL);
    if (trust) CFRelease(trust);
    CFRelease(policy); CFRelease(name); CFRelease(chain);
    if (trusted && !pinned) { result = 2; goto end; }
    pthread_mutex_lock(&s->certificate_lock);
    s->certificate_waiting = true; s->certificate_accepted = false;
    pthread_mutex_unlock(&s->certificate_lock);
    if (s->callbacks.certificate)
        s->callbacks.certificate(s->user, host, subject ? subject : "", issuer ? issuer : "", fingerprint, pinned);
    else mr_certificate_reply(s, false);
    struct timespec until; clock_gettime(CLOCK_REALTIME, &until); until.tv_sec += 120;
    pthread_mutex_lock(&s->certificate_lock);
    while (s->certificate_waiting && !atomic_load(&s->stop)) {
        if (pthread_cond_timedwait(&s->certificate_condition, &s->certificate_lock, &until) != 0) break;
    }
    result = s->certificate_accepted && !atomic_load(&s->stop) ? 2 : 0;
    s->certificate_waiting = false;
    pthread_mutex_unlock(&s->certificate_lock);
end:
    free(fingerprint); free(subject); free(issuer); free(pem);
    freerdp_certificate_free(certificate);
    return result;
}

static BOOL begin_paint(rdpContext *context) {
    context->gdi->primary->hdc->hwnd->invalid->null = true;
    return true;
}
static BOOL end_paint(rdpContext *context) {
    rdpGdi *gdi = context->gdi;
    if (gdi->primary->hdc->hwnd->invalid->null) return true;
    MRSession *s = owner(context);
    size_t size = (size_t)gdi->stride * gdi->height;
    if (gdi->width <= 0 || gdi->height <= 0 || size > 512u * 1024u * 1024u) return false;
    pthread_mutex_lock(&s->frame_lock);
    if (size > s->frame_capacity) {
        uint8_t *buffer = realloc(s->frame, size);
        if (!buffer) { pthread_mutex_unlock(&s->frame_lock); return false; }
        s->frame = buffer; s->frame_capacity = size;
    }
    if (s->width != (uint32_t)gdi->width || s->height != (uint32_t)gdi->height || s->stride != gdi->stride) {
        memcpy(s->frame, gdi->primary_buffer, size);
        s->frame_copied_bytes += size;
    } else {
        const GDI_RGN *dirty = gdi->primary->hdc->hwnd->invalid;
        int64_t left = dirty->x < 0 ? 0 : dirty->x;
        int64_t top = dirty->y < 0 ? 0 : dirty->y;
        int64_t right = (int64_t)dirty->x + dirty->w;
        int64_t bottom = (int64_t)dirty->y + dirty->h;
        if (right > gdi->width) right = gdi->width;
        if (bottom > gdi->height) bottom = gdi->height;
        if (right > left && bottom > top) {
            size_t row = (size_t)(right - left) * 4;
            for (int64_t y = top; y < bottom; y++) {
                size_t offset = (size_t)y * gdi->stride + (size_t)left * 4;
                memcpy(s->frame + offset, gdi->primary_buffer + offset, row);
            }
            s->frame_copied_bytes += row * (size_t)(bottom - top);
        }
    }
    s->frame_size = size; s->width = gdi->width; s->height = gdi->height; s->stride = gdi->stride;
    pthread_mutex_unlock(&s->frame_lock);
    if (s->callbacks.frame) s->callbacks.frame(s->user);
    return true;
}
static BOOL desktop_resize(rdpContext *context) {
    return gdi_resize(context->gdi, freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth),
                      freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight));
}
static BOOL pointer_new(rdpContext *context, rdpPointer *pointer) { (void)context; (void)pointer; return true; }
static void pointer_free(rdpContext *context, rdpPointer *pointer) { (void)context; (void)pointer; }
static BOOL pointer_set(rdpContext *context, rdpPointer *pointer) {
    MRSession *s = owner(context);
    if (pointer->width > 512 || pointer->height > 512) return false;
    size_t size = (size_t)pointer->width * pointer->height * 4;
    BYTE *pixels = calloc(1, size);
    if (!pixels) return false;
    BOOL ok = freerdp_image_copy_from_pointer_data(pixels, PIXEL_FORMAT_BGRA32, pointer->width * 4,
        0, 0, pointer->width, pointer->height, pointer->xorMaskData, pointer->lengthXorMask,
        pointer->andMaskData, pointer->lengthAndMask, pointer->xorBpp, &context->gdi->palette);
    if (ok && s->callbacks.cursor) s->callbacks.cursor(s->user, pixels, pointer->width, pointer->height,
        pointer->xPos, pointer->yPos, 1);
    free(pixels); return ok;
}
static BOOL pointer_null(rdpContext *context) {
    MRSession *s = owner(context);
    if (s->callbacks.cursor) s->callbacks.cursor(s->user, NULL, 0, 0, 0, 0, 0);
    return true;
}
static BOOL pointer_default(rdpContext *context) {
    MRSession *s = owner(context);
    if (s->callbacks.cursor) s->callbacks.cursor(s->user, NULL, 0, 0, 0, 0, 2);
    return true;
}
static UINT display_caps(DispClientContext *context, UINT32 monitors, UINT32 a, UINT32 b) {
    (void)monitors;
    MRSession *s = context->custom;
    pthread_mutex_lock(&s->display_lock);
    s->display_max_area = (uint64_t)a * b;
    s->display_ready = true;
    pthread_mutex_unlock(&s->display_lock);
    pthread_mutex_lock(&s->input_lock); s->resize_pending = true; pthread_mutex_unlock(&s->input_lock);
    SetEvent(s->wake);
    if (s->callbacks.display) s->callbacks.display(s->user, true);
    return CHANNEL_RC_OK;
}
static void channel_connected(void *context, const ChannelConnectedEventArgs *event) {
    MRSession *s = owner(context);
    if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) {
        pthread_mutex_lock(&s->display_lock);
        s->display = event->pInterface;
        s->display->custom = s; s->display->DisplayControlCaps = display_caps;
        pthread_mutex_unlock(&s->display_lock);
    } else freerdp_client_OnChannelConnectedEventHandler(context, event);
}
static void channel_disconnected(void *context, const ChannelDisconnectedEventArgs *event) {
    MRSession *s = owner(context);
    if (strcmp(event->name, DISP_DVC_CHANNEL_NAME) == 0) {
        pthread_mutex_lock(&s->display_lock);
        s->display = NULL; s->display_ready = false;
        pthread_mutex_unlock(&s->display_lock);
        if (s->callbacks.display) s->callbacks.display(s->user, false);
    } else freerdp_client_OnChannelDisconnectedEventHandler(context, event);
}
static void connection_state(void *context, const StateChangedEventArgs *event) {
    if (event->newState == CONNECTION_STATE_NLA || event->newState == CONNECTION_STATE_SECURE_SETTINGS_EXCHANGE)
        state(owner(context), 4, 0);
}
static BOOL pre_connect(freerdp *instance) {
    return PubSub_SubscribeChannelConnected(instance->context->pubSub, channel_connected) >= 0
        && PubSub_SubscribeChannelDisconnected(instance->context->pubSub, channel_disconnected) >= 0
        && PubSub_SubscribeStateChanged(instance->context->pubSub, connection_state) >= 0;
}
static BOOL post_connect(freerdp *instance) {
    if (!gdi_init(instance, PIXEL_FORMAT_BGRX32)) return false;
    rdpContext *context = instance->context;
    context->update->BeginPaint = begin_paint; context->update->EndPaint = end_paint;
    context->update->DesktopResize = desktop_resize;
    rdpPointer pointer = {0}; pointer.size = sizeof(rdpPointer);
    pointer.New = pointer_new; pointer.Free = pointer_free; pointer.Set = pointer_set;
    pointer.SetNull = pointer_null; pointer.SetDefault = pointer_default;
    graphics_register_pointer(context->graphics, &pointer);
    MRSession *s = owner(context); atomic_store(&s->connected, true); state(s, 2, 0);
    return true;
}
static void post_disconnect(freerdp *instance) {
    PubSub_UnsubscribeChannelConnected(instance->context->pubSub, channel_connected);
    PubSub_UnsubscribeChannelDisconnected(instance->context->pubSub, channel_disconnected);
    PubSub_UnsubscribeStateChanged(instance->context->pubSub, connection_state);
    gdi_free(instance);
}
static BOOL client_new(freerdp *instance, rdpContext *context) {
    (void)context;
    instance->PreConnect = pre_connect; instance->PostConnect = post_connect;
    instance->PostDisconnect = post_disconnect; instance->AuthenticateEx = authenticate;
    instance->VerifyX509Certificate = verify_certificate;
    return true;
}

MRSession *mr_session_new(const MRConfiguration *config, MRCallbacks callbacks, void *user) {
    if (!config || !config->host || !config->port || config->width < 200 || config->height < 200
        || config->width > 8192 || config->height > 8192 || config->width % 2
        || config->desktop_scale < 100 || config->desktop_scale > 500) return NULL;
    pthread_once(&logging_once, quiet_logging);
    MRSession *s = calloc(1, sizeof(MRSession));
    if (!s) return NULL;
    pthread_mutex_init(&s->input_lock, NULL); pthread_mutex_init(&s->frame_lock, NULL);
    pthread_mutex_init(&s->display_lock, NULL);
    pthread_mutex_init(&s->certificate_lock, NULL); pthread_cond_init(&s->certificate_condition, NULL);
    atomic_init(&s->stop, false); atomic_init(&s->connected, false); atomic_init(&s->error, 0);
    s->callbacks = callbacks; s->user = user;
    s->wake = CreateEvent(NULL, true, false, NULL);
    RDP_CLIENT_ENTRY_POINTS entry = {0}; entry.Size = sizeof(entry); entry.Version = RDP_CLIENT_INTERFACE_VERSION;
    entry.ContextSize = sizeof(MRContext); entry.ClientNew = client_new;
    s->context = freerdp_client_context_new(&entry);
    if (!s->context || !s->wake) { mr_session_free(s); return NULL; }
    ((MRContext *)s->context)->owner = s;
    s->fingerprint = strdup(config->fingerprint ? config->fingerprint : "");
    if (!s->fingerprint) { mr_session_free(s); return NULL; }
    s->requested_width = config->width; s->requested_height = config->height;
    s->requested_scale = config->desktop_scale;
    rdpSettings *settings = s->context->settings;
#define SET_BOOL(key, value) if (!freerdp_settings_set_bool(settings, FreeRDP_##key, value)) goto fail
#define SET_UINT(key, value) if (!freerdp_settings_set_uint32(settings, FreeRDP_##key, value)) goto fail
#define SET_STRING(key, value) if (!freerdp_settings_set_string(settings, FreeRDP_##key, value)) goto fail
    SET_STRING(ServerHostname, config->host); SET_UINT(ServerPort, config->port);
    SET_STRING(Username, config->username ? config->username : "");
    SET_STRING(Domain, config->domain ? config->domain : "");
    SET_STRING(Password, config->password ? config->password : "");
    SET_UINT(DesktopWidth, config->width); SET_UINT(DesktopHeight, config->height);
    SET_UINT(DesktopScaleFactor, config->desktop_scale); SET_UINT(DeviceScaleFactor, 100);
    SET_UINT(ColorDepth, 32); SET_UINT(TcpConnectTimeout, 10000);
    SET_BOOL(NlaSecurity, true); SET_BOOL(TlsSecurity, true); SET_BOOL(RdpSecurity, false);
    SET_BOOL(Authentication, true); SET_BOOL(IgnoreCertificate, false);
    SET_BOOL(ExternalCertificateManagement, true); SET_BOOL(UseCommonStdioCallbacks, false);
    SET_BOOL(AutoReconnectionEnabled, false); SET_BOOL(RedirectClipboard, false);
    SET_BOOL(SoftwareGdi, true); SET_BOOL(SupportGraphicsPipeline, true);
    SET_BOOL(GfxH264, true); SET_BOOL(GfxAVC444, true); SET_BOOL(GfxAVC444v2, true);
    SET_BOOL(DynamicResolutionUpdate, true); SET_BOOL(SupportDisplayControl, true);
#undef SET_BOOL
#undef SET_UINT
#undef SET_STRING
    return s;
fail:
    mr_session_free(s); return NULL;
}

static void clear_held(MRSession *s) {
    rdpInput *input = s->context->input;
    for (uint32_t i = 0; i < 512; i++) if (s->keys[i]) {
        if (atomic_load(&s->connected)) (void)freerdp_input_send_keyboard_event_ex(input, false, false, i);
        s->keys[i] = false;
    }
    for (uint16_t bit = PTR_FLAGS_BUTTON1; bit <= PTR_FLAGS_BUTTON3; bit <<= 1) if (s->buttons & bit)
        if (atomic_load(&s->connected)) (void)freerdp_input_send_mouse_event(input, bit, s->pointer_x, s->pointer_y);
    s->buttons = 0;
}
static BOOL drain_input(MRSession *s) {
    MRInput items[1024]; size_t count; bool cleanup, resize, synchronize;
    uint32_t width, height, scale, toggles;
    pthread_mutex_lock(&s->input_lock);
    ResetEvent(s->wake);
    count = s->count;
    for (size_t i = 0; i < count; i++) items[i] = s->input[(s->head + i) % 1024];
    s->head = 0; s->count = 0; cleanup = s->cleanup; s->cleanup = false;
    resize = s->resize_pending; width = s->requested_width; height = s->requested_height; scale = s->requested_scale;
    s->resize_pending = false;
    synchronize = s->synchronize_pending && s->input_enabled; toggles = s->toggles;
    s->synchronize_pending = false;
    pthread_mutex_unlock(&s->input_lock);
    if (cleanup) clear_held(s);
    if (synchronize && !freerdp_input_send_synchronize_event(s->context->input, toggles)) return false;
    for (size_t i = 0; i < count; i++) {
        MRInput event = items[i];
        pthread_mutex_lock(&s->input_lock);
        bool current = s->input_enabled && event.epoch == s->input_epoch;
        bool release = s->cleanup; s->cleanup = false;
        pthread_mutex_unlock(&s->input_lock);
        if (release) clear_held(s);
        if (!current || atomic_load(&s->stop)) continue;
        if (event.pointer) {
            s->pointer_x = event.x; s->pointer_y = event.y;
            uint16_t button = event.flags & (PTR_FLAGS_BUTTON1 | PTR_FLAGS_BUTTON2 | PTR_FLAGS_BUTTON3);
            if (event.flags & PTR_FLAGS_DOWN) s->buttons |= button; else s->buttons &= ~button;
            if (!freerdp_input_send_mouse_event(s->context->input, event.flags, event.x, event.y)) return false;
        } else {
            if (event.key < 512) s->keys[event.key] = event.down;
            if (!freerdp_input_send_keyboard_event_ex(s->context->input, event.down, event.repeat, event.key)) return false;
        }
    }
    pthread_mutex_lock(&s->display_lock);
    if (resize && s->display && s->display_ready) {
        if (s->display_max_area && (uint64_t)width * height > s->display_max_area) {
            if (s->callbacks.display) s->callbacks.display(s->user, false);
            pthread_mutex_unlock(&s->display_lock);
            return true;
        }
        DISPLAY_CONTROL_MONITOR_LAYOUT layout = {0};
        layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY; layout.Width = width; layout.Height = height;
        layout.PhysicalWidth = 300; layout.PhysicalHeight = 200;
        layout.DesktopScaleFactor = scale; layout.DeviceScaleFactor = 100;
        if (s->display->SendMonitorLayout(s->display, 1, &layout) != CHANNEL_RC_OK) {
            if (s->callbacks.display) s->callbacks.display(s->user, false);
        }
    }
    pthread_mutex_unlock(&s->display_lock);
    return true;
}
void mr_session_run(MRSession *s) {
    if (!s || atomic_load(&s->stop)) return;
    state(s, 1, 0);
    freerdp *instance = s->context->instance;
    BOOL ok = freerdp_connect(instance);
    if (ok) {
        while (!atomic_load(&s->stop) && !freerdp_shall_disconnect_context(s->context)) {
            HANDLE handles[MAXIMUM_WAIT_OBJECTS]; handles[0] = s->wake;
            DWORD count = freerdp_get_event_handles(s->context, handles + 1, MAXIMUM_WAIT_OBJECTS - 1);
            if (!count) break;
            DWORD result = WaitForMultipleObjects(count + 1, handles, false, INFINITE);
            if (result == WAIT_FAILED || atomic_load(&s->stop)) break;
            if (!drain_input(s) || !freerdp_check_event_handles(s->context)) break;
        }
        clear_held(s);
    }
    uint32_t error = freerdp_get_last_error(s->context);
    atomic_store(&s->connected, false);
    (void)freerdp_disconnect(instance);
    state(s, atomic_load(&s->stop) ? 0 : 3, error);
}
void mr_session_cancel(MRSession *s) {
    if (!s) return;
    atomic_store(&s->stop, true); mr_certificate_reply(s, false); SetEvent(s->wake);
    if (s->context) (void)freerdp_abort_connect_context(s->context);
}
void mr_session_free(MRSession *s) {
    if (!s) return;
    if (s->context) freerdp_client_context_free(s->context);
    if (s->wake) CloseHandle(s->wake);
    free(s->frame); free(s->fingerprint);
    pthread_cond_destroy(&s->certificate_condition);
    pthread_mutex_destroy(&s->certificate_lock); pthread_mutex_destroy(&s->frame_lock);
    pthread_mutex_destroy(&s->display_lock);
    pthread_mutex_destroy(&s->input_lock); free(s);
}
void mr_certificate_reply(MRSession *s, bool accept) {
    pthread_mutex_lock(&s->certificate_lock);
    s->certificate_accepted = accept; s->certificate_waiting = false;
    pthread_cond_signal(&s->certificate_condition); pthread_mutex_unlock(&s->certificate_lock);
}
void mr_input_enable(MRSession *s, bool enabled) {
    pthread_mutex_lock(&s->input_lock);
    s->input_enabled = enabled;
    if (!enabled) { s->input_epoch++; s->head = 0; s->count = 0; s->cleanup = true; }
    pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake);
}
void mr_synchronize(MRSession *s, uint32_t toggles) {
    pthread_mutex_lock(&s->input_lock);
    s->toggles = toggles & 7; s->synchronize_pending = s->input_enabled;
    pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake);
}
static bool enqueue(MRSession *s, MRInput event) {
    if (!s || !atomic_load(&s->connected) || atomic_load(&s->stop)) return false;
    pthread_mutex_lock(&s->input_lock);
    if (!s->input_enabled) { pthread_mutex_unlock(&s->input_lock); return false; }
    if (event.pointer && event.flags == PTR_FLAGS_MOVE && s->count > 0) {
        MRInput *last = &s->input[(s->head + s->count - 1) % 1024];
        if (last->pointer && last->flags == PTR_FLAGS_MOVE && last->epoch == s->input_epoch) {
            last->x = event.x; last->y = event.y;
            pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake); return true;
        }
    }
    if (s->count == 1024) {
        s->cleanup = true; s->input_enabled = false; s->count = 0;
        atomic_store(&s->stop, true);
        pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake); return false;
    }
    event.epoch = s->input_epoch;
    s->input[(s->head + s->count) % 1024] = event; s->count++;
    pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake); return true;
}
bool mr_key(MRSession *s, uint32_t code, bool down, bool repeat) {
    if (code >= 512) return false;
    return enqueue(s, (MRInput){.key = code, .down = down, .repeat = repeat});
}
bool mr_pointer(MRSession *s, uint16_t flags, uint16_t x, uint16_t y) {
    return enqueue(s, (MRInput){.flags = flags, .x = x, .y = y, .pointer = true});
}
void mr_resize(MRSession *s, uint32_t width, uint32_t height, uint32_t scale) {
    if (width < 200 || height < 200 || width > 8192 || height > 8192 || width % 2 || scale < 100 || scale > 500) return;
    pthread_mutex_lock(&s->input_lock);
    s->requested_width = width; s->requested_height = height; s->requested_scale = scale; s->resize_pending = true;
    pthread_mutex_unlock(&s->input_lock); SetEvent(s->wake);
}
size_t mr_copy_frame(MRSession *s, uint8_t *buffer, size_t capacity, uint32_t *width, uint32_t *height, uint32_t *stride) {
    pthread_mutex_lock(&s->frame_lock);
    size_t size = s->frame_size; *width = s->width; *height = s->height; *stride = s->stride;
    if (buffer && capacity >= size && size) memcpy(buffer, s->frame, size);
    pthread_mutex_unlock(&s->frame_lock); return size;
}
uint32_t mr_last_error(MRSession *s) { return atomic_load(&s->error); }
