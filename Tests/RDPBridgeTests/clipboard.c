#include "../../Sources/RDPBridge/RDPBridge.c"
#include <assert.h>
#include <stdio.h>

static unsigned requests, acknowledgements, deliveries, capabilities, announcements;
static uint64_t delivered_generation;
static UINT request_text(CliprdrClientContext *context, const CLIPRDR_FORMAT_DATA_REQUEST *request) {
    (void)context;
    assert(request->requestedFormatId == CF_UNICODETEXT);
    requests++;
    return CHANNEL_RC_OK;
}
static UINT acknowledge(CliprdrClientContext *context, const CLIPRDR_FORMAT_LIST_RESPONSE *response) {
    (void)context;
    assert(response->common.msgFlags == CB_RESPONSE_OK);
    acknowledgements++;
    return CHANNEL_RC_OK;
}
static UINT client_capabilities(CliprdrClientContext *context, const CLIPRDR_CAPABILITIES *caps) {
    (void)context;
    assert(caps->cCapabilitiesSets == 1);
    CLIPRDR_GENERAL_CAPABILITY_SET *general = (CLIPRDR_GENERAL_CAPABILITY_SET *)caps->capabilitySets;
    assert(general->version == CB_CAPS_VERSION_2 && general->generalFlags == CB_USE_LONG_FORMAT_NAMES);
    capabilities++;
    return CHANNEL_RC_OK;
}
static UINT client_formats(CliprdrClientContext *context, const CLIPRDR_FORMAT_LIST *formats) {
    (void)context;
    assert(formats->numFormats == 0 && formats->formats == NULL);
    announcements++;
    return CHANNEL_RC_OK;
}
static void receive_text(void *user, const uint8_t *data, size_t length, uint64_t generation) {
    (void)user;
    assert(length == 4 && data[0] == 'A');
    delivered_generation = generation;
    deliveries++;
}
int main(void) {
    MRConfiguration config = {.host = "test.invalid", .port = 3389, .width = 1600, .height = 1000, .desktop_scale = 200};
    MRSession *s = mr_session_new(&config, (MRCallbacks){.clipboard = receive_text}, NULL);
    assert(s);
    assert(freerdp_settings_get_bool(s->context->settings, FreeRDP_RedirectClipboard));
    assert(freerdp_settings_get_uint32(s->context->settings, FreeRDP_ClipboardFeatureMask) == (CLIPRDR_FLAG_REMOTE_TO_LOCAL | CLIPRDR_FLAG_LOCAL_TO_REMOTE));
    CliprdrClientContext clipboard = {.ClientFormatDataRequest = request_text,
        .ClientFormatListResponse = acknowledge, .ClientCapabilities = client_capabilities,
        .ClientFormatList = client_formats};
    ChannelConnectedEventArgs channel = {.name = CLIPRDR_SVC_CHANNEL_NAME, .pInterface = &clipboard};
    channel_connected(s->context, &channel);
    assert(clipboard.custom == s && clipboard.ServerFormatList && clipboard.ServerFormatDataResponse);
    CLIPRDR_MONITOR_READY ready = {0};
    assert(clipboard.MonitorReady(&clipboard, &ready) == CHANNEL_RC_OK);
    assert(capabilities == 1 && announcements == 1);
    CLIPRDR_FORMAT unicode = {.formatId = CF_UNICODETEXT};
    CLIPRDR_FORMAT_LIST formats = {.numFormats = 1, .formats = &unicode};
    BYTE data[] = {'A', 0, 0, 0};
    CLIPRDR_FORMAT_DATA_RESPONSE response = {
        .common = {.msgFlags = CB_RESPONSE_OK, .dataLen = sizeof(data)}, .requestedFormatData = data
    };
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(requests == 0 && acknowledgements == 1);
    mr_clipboard_enable(s, true, 1);
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(requests == 1);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 1 && delivered_generation == 1);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 1);

    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(requests == 2);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 1 && requests == 3);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 2);

    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    mr_clipboard_enable(s, false, 2);
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    mr_clipboard_enable(s, true, 3);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 2 && requests == 4);
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 3 && delivered_generation == 3);

    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    mr_clipboard_enable(s, false, 4); mr_clipboard_enable(s, true, 5);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 3 && requests == 6);

    unicode.formatId = CF_DIB;
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(requests == 6);
    unicode.formatId = CF_UNICODETEXT;
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    unicode.formatId = CF_HDROP;
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 3 && requests == 7);

    unicode.formatId = CF_UNICODETEXT;
    for (unsigned i = 0; i < 5; i++) {
        assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
        CLIPRDR_FORMAT_DATA_RESPONSE invalid = response;
        if (i == 0) invalid.common.msgFlags = CB_RESPONSE_FAIL;
        if (i == 1) invalid.common.dataLen = 3;
        if (i == 2) invalid.common.dataLen = 16u * 1024u * 1024u + 2;
        if (i == 3) invalid.requestedFormatData = NULL;
        if (i == 4) invalid.common.dataLen = 0;
        assert(clipboard_data(&clipboard, &invalid) == CHANNEL_RC_OK);
        assert(deliveries == 3 && !s->clipboard_pending);
    }
    assert(clipboard_formats(&clipboard, &formats) == CHANNEL_RC_OK);
    mr_session_cancel(s);
    assert(clipboard_data(&clipboard, &response) == CHANNEL_RC_OK);
    assert(deliveries == 3);
    mr_session_free(s);
    puts("PASS clipboard negotiation, one-way text, rapid copies, disabled/stale responses, malformed sizes and cancellation");
    return 0;
}
