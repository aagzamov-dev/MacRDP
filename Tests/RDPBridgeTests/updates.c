#define freerdp_input_send_unicode_keyboard_event test_unicode
#define freerdp_input_send_keyboard_event_ex test_keyboard
#include "../../Sources/RDPBridge/RDPBridge.c"
#undef freerdp_input_send_unicode_keyboard_event
#undef freerdp_input_send_keyboard_event_ex
#include <assert.h>
#include <stdio.h>

static unsigned unicode_down, unicode_up, key_down, key_up, offers, data_sent;
static bool invalidate_text;
static unsigned layouts;
static uint32_t layout_width, layout_height, layout_scale;
static bool resize_during_send;
static UINT monitor_layout(DispClientContext *context, UINT32 count,
                           DISPLAY_CONTROL_MONITOR_LAYOUT *layout) {
    assert(count == 1 && layout->DeviceScaleFactor == 100);
    layouts++; layout_width = layout->Width; layout_height = layout->Height;
    layout_scale = layout->DesktopScaleFactor;
    if (resize_during_send) {
        resize_during_send = false;
        mr_resize(context->custom, 3200, 2000, 200);
    }
    return CHANNEL_RC_OK;
}
BOOL test_unicode(rdpInput *input, UINT16 flags, UINT16 code) {
    assert(code != 0);
    if (flags & KBD_FLAGS_RELEASE) unicode_up++; else unicode_down++;
    if (invalidate_text && !flags) { invalidate_text = false; mr_input_enable(owner(input->context), false); }
    return true;
}
BOOL test_keyboard(rdpInput *input, BOOL down, BOOL repeat, UINT32 code) {
    (void)input; (void)repeat; (void)code;
    if (down) key_down++; else key_up++;
    return true;
}
static UINT offer(CliprdrClientContext *context, const CLIPRDR_FORMAT_LIST *formats) {
    (void)context;
    assert(formats->numFormats == 1 && formats->formats[0].formatId == CF_UNICODETEXT); offers++;
    return CHANNEL_RC_OK;
}
static UINT data_response(CliprdrClientContext *context, const CLIPRDR_FORMAT_DATA_RESPONSE *response) {
    (void)context;
    if (response->common.msgFlags == CB_RESPONSE_OK) {
        assert(response->common.dataLen == 4 && response->requestedFormatData[0] == 'X'); data_sent++;
    } else assert(response->common.msgFlags == CB_RESPONSE_FAIL);
    return CHANNEL_RC_OK;
}
int main(void) {
    MRConfiguration config = {.host = "test.invalid", .port = 3389, .width = 3840, .height = 2160, .desktop_scale = 200};
    MRSession *s = mr_session_new(&config, (MRCallbacks){0}, NULL); assert(s);
    GDI_RGN region = {.w = 3840, .h = 2160}; GDI_WND window = {.invalid = &region};
    GDI_DC dc = {.hwnd = &window}; gdiBitmap bitmap = {.hdc = &dc};
    rdpGdi gdi = {.width = 3840, .height = 2160, .stride = 3840 * 4, .primary = &bitmap};
    size_t capacity = (size_t)gdi.stride * gdi.height;
    gdi.primary_buffer = malloc(capacity); uint8_t *output = malloc(capacity); assert(gdi.primary_buffer && output);
    s->context->gdi = &gdi; memset(gdi.primary_buffer, 0x11, capacity);
    assert(end_paint(s->context));
    MRFrameInfo info;
    assert(mr_copy_frame_update(s, NULL, 0, false, &info) == capacity);
    assert(mr_copy_frame_update(s, output, 16, false, &info) == capacity && s->frame_dirty);
    assert(mr_copy_frame_update(s, output, capacity, false, &info) == capacity);
    assert(info.dirty_width == 3840 && info.dirty_height == 2160 && info.generation == 1);
    assert(mr_copy_frame_update(s, output, capacity, false, &info) == 0);
    uint64_t copied = s->snapshot_bytes;
    memset(gdi.primary_buffer, 0x22, capacity);
    region.x = 10; region.y = 20; region.w = 32; region.h = 32;
    assert(end_paint(s->context));
    assert(mr_copy_frame_update(s, output, capacity, false, &info) == capacity);
    assert(info.x == 10 && info.y == 20 && info.dirty_width == 32 && info.dirty_height == 32);
    assert(s->snapshot_bytes - copied == 4096);
    assert(output[0] == 0x11 && output[20 * info.stride + 10 * 4] == 0x22);
    region.x = 0; region.y = 0; region.w = 10; region.h = 10; assert(end_paint(s->context));
    region.x = 100; region.y = 100; assert(end_paint(s->context));
    assert(mr_copy_frame_update(s, output, capacity, false, &info) == capacity);
    assert(info.x == 0 && info.y == 0 && info.dirty_width == 110 && info.dirty_height == 110);
    assert(mr_copy_frame_update(s, output, capacity, true, &info) == capacity);
    assert(info.dirty_width == 3840 && info.dirty_height == 2160);
    gdi.width = 1002; gdi.height = 600; gdi.stride = 4008;
    region.w = 1; region.h = 1; memset(gdi.primary_buffer, 0x33, capacity); assert(end_paint(s->context));
    assert(mr_copy_frame_update(s, output, capacity, false, &info) == 4096 * 600);
    assert(info.generation == 2 && info.dirty_width == 1002 && info.dirty_height == 600 && info.stride == 4096);
    assert(output[599 * info.stride + 1001 * 4] == 0x33);
    puts("PASS 4K patch snapshot: 4,096 bytes instead of 33,177,600; accumulated regions, retry, idle, resize and aligned rows");
    free(gdi.primary_buffer); free(output); s->context->gdi = NULL;
    DispClientContext display = {.custom = s, .SendMonitorLayout = monitor_layout};
    s->display = &display;
    mr_resize(s, 2400, 1600, 200); assert(drain_input(s)); assert(layouts == 0);
    mr_resize(s, 3024, 1898, 200); assert(drain_input(s)); assert(layouts == 0);
    assert(apply_initial_layout(s));
    assert(freerdp_settings_get_uint32(s->context->settings, FreeRDP_DesktopWidth) == 3024);
    assert(freerdp_settings_get_uint32(s->context->settings, FreeRDP_DesktopHeight) == 1898);
    assert(freerdp_settings_get_uint32(s->context->settings, FreeRDP_DesktopScaleFactor) == 200);
    assert(freerdp_settings_get_uint32(s->context->settings, FreeRDP_DeviceScaleFactor) == 100);
    assert(display_caps(&display, 1, 8192, 8192) == CHANNEL_RC_OK);
    assert(drain_input(s));
    assert(layouts == 1 && layout_width == 3024 && layout_height == 1898 && layout_scale == 200);
    mr_resize(s, 3024, 1898, 150); assert(drain_input(s));
    assert(layouts == 2 && layout_scale == 150);
    mr_resize(s, 3000, 1900, 200); resize_during_send = true;
    assert(drain_input(s)); assert(layouts == 3 && layout_width == 3000);
    assert(drain_input(s)); assert(layouts == 4 && layout_width == 3200 && layout_height == 2000);
    ChannelDisconnectedEventArgs disconnected = {.name = DISP_DVC_CHANNEL_NAME};
    channel_disconnected(s->context, &disconnected);
    mr_resize(s, 3072, 1920, 200); assert(drain_input(s)); assert(layouts == 4);
    ChannelConnectedEventArgs connected = {.name = DISP_DVC_CHANNEL_NAME, .pInterface = &display};
    channel_connected(s->context, &connected);
    assert(display_caps(&display, 1, 8192, 8192) == CHANNEL_RC_OK);
    assert(drain_input(s));
    assert(layouts == 5 && layout_width == 3072 && layout_height == 1920 && layout_scale == 200);
    s->display = NULL; s->display_ready = false;
    puts("PASS latest pre-capability Retina layout, scale-only resize, newer layout during send and display-channel reopen");
    atomic_store(&s->connected, true); mr_input_enable(s, true);
    const uint16_t text[] = {0x0410, 0xd83d, 0xde00};
    assert(mr_text(s, text, 3)); assert(drain_input(s)); assert(unicode_down == 3 && unicode_up == 3);
    assert(!mr_text(s, text, 513));
    assert(mr_text(s, text, 3)); invalidate_text = true; assert(drain_input(s));
    assert(unicode_down == 4 && unicode_up == 4 && s->count == 0);
    assert(!mr_text(s, text, 3));
    puts("PASS Unicode pairs, supplementary characters, release during send and disabled/oversized rejection");
    mr_input_enable(s, true);
    CliprdrClientContext clipboard = {.custom = s, .ClientFormatList = offer, .ClientFormatDataResponse = data_response};
    s->clipboard = &clipboard; atomic_store(&s->clipboard_available, true);
    const uint8_t bytes[] = {'X', 0, 0, 0};
    s->format_announcement = 1;
    assert(mr_paste(s, bytes, sizeof(bytes))); assert(drain_input(s)); assert(offers == 0);
    CLIPRDR_FORMAT_LIST_RESPONSE ack = {.common.msgFlags = CB_RESPONSE_OK};
    assert(clipboard_offer_response(&clipboard, &ack) == CHANNEL_RC_OK);
    assert(s->count == 0); assert(drain_input(s)); assert(offers == 1);
    assert(clipboard_offer_response(&clipboard, &ack) == CHANNEL_RC_OK);
    assert(s->count == 4); assert(drain_input(s)); assert(key_down == 2 && key_up == 2);
    CLIPRDR_FORMAT_DATA_REQUEST request = {.requestedFormatId = CF_UNICODETEXT};
    assert(clipboard_local_data(&clipboard, &request) == CHANNEL_RC_OK && data_sent == 1);
    assert(mr_paste(s, bytes, sizeof(bytes))); assert(drain_input(s));
    mr_input_enable(s, false); mr_input_enable(s, true);
    assert(clipboard_offer_response(&clipboard, &ack) == CHANNEL_RC_OK && s->count == 0);
    assert(clipboard_local_data(&clipboard, &request) == CHANNEL_RC_OK && data_sent == 1);
    mr_session_cancel(s); assert(!mr_paste(s, bytes, sizeof(bytes)));
    mr_session_free(s);
    puts("PASS explicit clipboard offer ordering, paste acknowledgement and stale focus/cancel cleanup");
}
