#define freerdp_input_send_keyboard_event_ex test_send_key
#define freerdp_input_send_mouse_event test_send_mouse
#include "../../Sources/RDPBridge/RDPBridge.c"
#undef freerdp_input_send_keyboard_event_ex
#undef freerdp_input_send_mouse_event
BOOL test_send_key(rdpInput *input, BOOL down, BOOL repeat, UINT32 code) {
    (void)repeat;
    return input->KeyboardEvent(input, (down ? 0 : KBD_FLAGS_RELEASE) | (code & 0x100 ? KBD_FLAGS_EXTENDED : 0), code & 0xff);
}
BOOL test_send_mouse(rdpInput *input, UINT16 flags, UINT16 x, UINT16 y) { return input->MouseEvent(input, flags, x, y); }
#include <assert.h>
#include <stdio.h>

static int downs, ups, releases;
static bool release_during_send;
static BOOL keyboard_event(rdpInput *input, UINT16 flags, UINT8 code) {
    (void)code;
    if (flags & KBD_FLAGS_RELEASE) ups++; else downs++;
    if (release_during_send && !(flags & KBD_FLAGS_RELEASE)) {
        release_during_send = false;
        MRSession *s = owner(input->context);
        mr_input_enable(s, false); mr_input_enable(s, true); releases++;
    }
    return true;
}
static BOOL mouse_event(rdpInput *input, UINT16 flags, UINT16 x, UINT16 y) {
    (void)input; (void)flags; (void)x; (void)y; return true;
}
static MRSession *session(void) {
    MRConfiguration config = {.host = "test.invalid", .port = 3389, .width = 1600, .height = 1000, .desktop_scale = 200};
    MRSession *s = mr_session_new(&config, (MRCallbacks){0}, NULL); assert(s);
    s->context->input->KeyboardEvent = keyboard_event;
    s->context->input->MouseEvent = mouse_event;
    atomic_store(&s->connected, true); mr_input_enable(s, true);
    return s;
}
int main(void) {
    MRSession *s = session();
    assert(mr_key(s, 0x1e, true, false)); assert(mr_key(s, 0x30, true, false)); assert(mr_key(s, 0x20, true, false));
    release_during_send = true;
    assert(drain_input(s));
    assert(downs == 1 && ups == 1 && releases == 1);
    assert(!s->keys[0x1e] && !s->keys[0x30] && !s->keys[0x20]);
    assert(mr_key(s, 0x2e, true, false)); assert(mr_key(s, 0x2e, false, false));
    assert(drain_input(s)); assert(downs == 2 && ups == 2);
    mr_input_enable(s, false); assert(!mr_key(s, 0x1e, true, false));
    mr_session_free(s);
    s = session();
    assert(mr_key(s, 0x1e, true, false)); assert(drain_input(s));
    for (int i = 0; i < 1024; i++) assert(mr_key(s, 0x30, true, true));
    assert(!mr_key(s, 0x30, false, false));
    assert(atomic_load(&s->stop) && !s->input_enabled && s->cleanup);
    assert(drain_input(s)); assert(!s->keys[0x1e] && s->count == 0);
    assert(downs == 3 && ups == 3);
    mr_session_free(s);
    s = session();
    for (int i = 0; i < 5000; i++) assert(mr_pointer(s, PTR_FLAGS_MOVE, (uint16_t)i, 20));
    assert(s->count == 1 && !atomic_load(&s->stop));
    assert(s->input[0].x == 4999);
    assert(mr_pointer(s, PTR_FLAGS_BUTTON1 | PTR_FLAGS_DOWN, 4999, 20));
    assert(mr_pointer(s, PTR_FLAGS_MOVE, 5000, 20));
    assert(s->count == 3);
    assert(drain_input(s));
    mr_session_free(s);
    s = session();
    GDI_RGN region = {0};
    GDI_WND window = {.invalid = &region};
    GDI_DC dc = {.hwnd = &window};
    gdiBitmap bitmap = {.hdc = &dc};
    rdpGdi test_gdi = {.width = 1600, .height = 1000, .stride = 6400, .primary = &bitmap};
    test_gdi.primary_buffer = malloc(1800 * 1200 * 4); assert(test_gdi.primary_buffer);
    s->context->gdi = &test_gdi;
    rdpGdi *gdi = s->context->gdi;
    GDI_RGN *dirty = &region;
    memset(gdi->primary_buffer, 0x11, (size_t)gdi->stride * gdi->height);
    dirty->null = false; dirty->x = 0; dirty->y = 0; dirty->w = gdi->width; dirty->h = gdi->height;
    assert(end_paint(s->context));
    uint64_t copied = s->frame_copied_bytes;
    memset(gdi->primary_buffer, 0x22, (size_t)gdi->stride * gdi->height);
    dirty->x = 10; dirty->y = 20; dirty->w = 32; dirty->h = 32;
    assert(end_paint(s->context));
    assert(s->frame_copied_bytes - copied == 32 * 32 * 4);
    assert(s->frame[0] == 0x11 && s->frame[20 * gdi->stride + 10 * 4] == 0x22);
    assert(s->frame[20 * gdi->stride + 42 * 4] == 0x11);
    copied = s->frame_copied_bytes;
    dirty->x = -5; dirty->y = -5; dirty->w = 10; dirty->h = 10;
    assert(end_paint(s->context));
    assert(s->frame_copied_bytes - copied == 5 * 5 * 4);
    gdi->width = 1800; gdi->height = 1200; gdi->stride = 7200;
    memset(gdi->primary_buffer, 0x33, 1800 * 1200 * 4);
    dirty = gdi->primary->hdc->hwnd->invalid;
    dirty->null = false; dirty->x = 0; dirty->y = 0; dirty->w = 1; dirty->h = 1;
    copied = s->frame_copied_bytes;
    assert(end_paint(s->context));
    assert(s->width == 1800 && s->height == 1200);
    assert(s->frame_copied_bytes - copied == (uint64_t)gdi->stride * 1200);
    free(gdi->primary_buffer); s->context->gdi = NULL; mr_session_free(s);
    puts("PASS pointer coalescing, button ordering, dirty-region copies, clipping and full resize snapshot");
    puts("PASS stale input epoch, mid-send release/resume, overflow, key-up cleanup and disabled queue");
    return 0;
}
