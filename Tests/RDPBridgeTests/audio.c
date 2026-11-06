#include "../../Sources/RDPBridge/RDPBridge.c"
#include <freerdp/addin.h>
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (int playback = 0; playback < 2; playback++) {
        for (int microphone = 0; microphone < 2; microphone++) {
            MRConfiguration config = {.host = "synthetic.invalid", .port = 3389,
                .width = 1600, .height = 1000, .desktop_scale = 200,
                .audio = playback, .microphone = microphone};
            MRSession *session = mr_session_new(&config, (MRCallbacks){0}, NULL);
            assert(session);
            rdpSettings *settings = session->context->settings;
            assert(freerdp_settings_get_bool(settings, FreeRDP_AudioPlayback) == playback);
            assert(freerdp_settings_get_bool(settings, FreeRDP_AudioCapture) == microphone);
            ADDIN_ARGV *input = freerdp_dynamic_channel_collection_find(settings, "audin");
            ADDIN_ARGV *dynamic = freerdp_dynamic_channel_collection_find(settings, "rdpsnd");
            ADDIN_ARGV *output = freerdp_static_channel_collection_find(settings, "rdpsnd");
            assert(!!input == microphone && !!output == playback && !!dynamic == playback);
            if (microphone) assert(input->argc == 2 && strcmp(input->argv[1], "sys:mac") == 0);
            if (playback) {
                assert(output->argc == 2 && strcmp(output->argv[1], "sys:mac") == 0);
                assert(dynamic->argc == 2 && strcmp(dynamic->argv[1], "sys:mac") == 0);
            }
            assert(freerdp_load_channel_addin_entry("audin", "mac", NULL, 0));
            assert(freerdp_load_channel_addin_entry("rdpsnd", "mac", NULL,
                FREERDP_ADDIN_CHANNEL_STATIC | FREERDP_ADDIN_CHANNEL_ENTRYEX));
            assert(freerdp_load_channel_addin_entry("rdpsnd", "mac", NULL,
                FREERDP_ADDIN_CHANNEL_DYNAMIC));
            mr_session_free(session);
        }
    }
    puts("PASS independent audio flags, explicit native Mac channels and installed input/output addin resolution; no device opened");
    return 0;
}
