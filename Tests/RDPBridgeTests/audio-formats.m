#include "../../build/hardware-decoding/FreeRDP-3.32.2/channels/audin/client/mac/audin_mac.m"
#include <assert.h>

int main(void) {
    AudinMacDevice device = {.isAuthorized = true};
    AUDIO_FORMAT format = {.wFormatTag = WAVE_FORMAT_PCM, .nChannels = 1,
        .nSamplesPerSec = 48000, .wBitsPerSample = 16};
    for (UINT16 channels = 1; channels <= 2; channels++) {
        format.nChannels = channels;
        assert(audin_mac_format_supported(&device.iface, &format));
        assert(audin_mac_set_format(&device.iface, &format, 480) == CHANNEL_RC_OK);
        assert(device.audioFormat.mChannelsPerFrame == channels);
        assert(device.audioFormat.mBytesPerFrame == channels * 2);
        assert(device.audioFormat.mSampleRate == 48000);
    }
    device.isAuthorized = false;
    assert(!audin_mac_format_supported(&device.iface, &format));
    assert(audin_mac_set_format(&device.iface, &format, 480) == ERROR_INVALID_PARAMETER);
    device.isAuthorized = true;
    for (UINT16 bits = 0; bits <= 32; bits += 8) {
        format.wBitsPerSample = bits;
        assert(!!audin_mac_format_supported(&device.iface, &format) == (bits == 16));
    }
    format.wBitsPerSample = 16;
    format.nChannels = 3;
    assert(!audin_mac_format_supported(&device.iface, &format));
    format.nChannels = 1; format.nSamplesPerSec = 0;
    assert(!audin_mac_format_supported(&device.iface, &format));
    format.nSamplesPerSec = 44100; format.wFormatTag = WAVE_FORMAT_ALAW;
    assert(!audin_mac_format_supported(&device.iface, &format));
    assert(!audin_mac_format_supported(NULL, &format));
    assert(!audin_mac_format_supported(&device.iface, NULL));
    assert(audin_mac_set_format(NULL, &format, 480) == ERROR_INVALID_PARAMETER);
    assert(audin_mac_set_format(&device.iface, NULL, 480) == ERROR_INVALID_PARAMETER);
    format.wFormatTag = WAVE_FORMAT_PCM;
    assert(audin_mac_set_format(&device.iface, &format, 0) == ERROR_INVALID_PARAMETER);
    puts("PASS native microphone mono/stereo 16-bit PCM geometry, permission gating and malformed-format rejection; no microphone accessed");
    return 0;
}
