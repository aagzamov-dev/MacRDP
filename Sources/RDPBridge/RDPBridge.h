#ifndef MACRDP_BRIDGE_H
#define MACRDP_BRIDGE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct MRSession MRSession;
typedef struct {
    const char *host, *username, *domain, *password, *fingerprint;
    uint16_t port;
    uint32_t width, height, desktop_scale;
} MRConfiguration;
typedef struct {
    void (*state)(void *, int, uint32_t);
    void (*frame)(void *);
    void (*certificate)(void *, const char *, const char *, const char *, const char *, bool);
    void (*cursor)(void *, const uint8_t *, uint32_t, uint32_t, uint32_t, uint32_t, int);
    void (*display)(void *, bool);
} MRCallbacks;

MRSession *mr_session_new(const MRConfiguration *, MRCallbacks, void *);
void mr_session_run(MRSession *);
void mr_session_cancel(MRSession *);
void mr_session_free(MRSession *);
void mr_certificate_reply(MRSession *, bool);
void mr_input_enable(MRSession *, bool);
void mr_synchronize(MRSession *, uint32_t);
bool mr_key(MRSession *, uint32_t, bool, bool);
bool mr_pointer(MRSession *, uint16_t, uint16_t, uint16_t);
void mr_resize(MRSession *, uint32_t, uint32_t, uint32_t);
size_t mr_copy_frame(MRSession *, uint8_t *, size_t, uint32_t *, uint32_t *, uint32_t *);
uint32_t mr_last_error(MRSession *);
#endif
