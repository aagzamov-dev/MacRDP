#include <freerdp/codec/h264.h>
#include <freerdp/codec/color.h>
#include <winpr/wlog.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
extern UINT32 freerdp_macrdp_decoder_backend(void);
extern void freerdp_macrdp_decoder_reset(void);
int main(int argc, char **argv) {
    assert(argc == 4);
    WLog_SetLogLevel(WLog_GetRoot(), WLOG_OFF);
    FILE *input = fopen(argv[1], "rb"); assert(input);
    fseek(input, 0, SEEK_END); long length = ftell(input); rewind(input);
    assert(length > 0 && length < 1000000);
    BYTE *data = calloc(1, (size_t)length + 64); assert(data);
    assert(fread(data, 1, (size_t)length, input) == (size_t)length); fclose(input);
    BYTE *pixels = calloc(64 * 64, 4); assert(pixels);
    H264_CONTEXT *ctx = h264_context_new(FALSE); assert(ctx);
    assert(h264_context_set_option(ctx, H264_CONTEXT_OPTION_HW_ACCEL, 1));
    assert(h264_context_reset(ctx, 64, 64));
    freerdp_macrdp_decoder_reset();
    RECTANGLE_16 rect = {0, 0, 64, 64};
    INT32 result = avc420_decompress(ctx, data, (UINT32)length, pixels, PIXEL_FORMAT_BGRA32, 64 * 4, 64, 64, &rect, 1);
    assert(result >= 0);
    UINT32 backend = freerdp_macrdp_decoder_backend();
    assert(backend == (UINT32)atoi(argv[3]));
    FILE *out = fopen(argv[2], "wb"); assert(out);
    assert(fwrite(pixels, 1, 64 * 64 * 4, out) == 64 * 64 * 4); fclose(out);
    printf("PASS synthetic AVC420 decode, backend=%u\n", backend);
    h264_context_free(ctx); free(data); free(pixels);
    return 0;
}
