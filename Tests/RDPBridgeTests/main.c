#include "RDPBridge.h"
#include <freerdp/freerdp.h>
#include <freerdp/peer.h>
#include <freerdp/channels/wtsvc.h>
#include <freerdp/channels/channels.h>
#include <freerdp/server/disp.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/crypto/privatekey.h>
#include <winpr/synch.h>
#include <winpr/wlog.h>
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <time.h>

typedef struct {
    int listener;
    const char *cert, *key;
    atomic_bool stop, activated, connected, certificate, changed, frame, finished;
    atomic_int key_down, key_up, mouse_down, mouse_up, layout_width, layout_height, layouts;
    atomic_bool display, authenticated;
    bool nla;
    int decision;
    MRSession *session;
} Fixture;
typedef struct { rdpContext base; Fixture *fixture; } PeerContext;
static double seconds(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static void wait_flag(atomic_bool *flag) {
    double until = seconds() + 12;
    while (!atomic_load(flag) && seconds() < until) usleep(1000);
    assert(atomic_load(flag));
}
static Fixture *fixture(rdpInput *input) { return ((PeerContext *)input->context)->fixture; }
static BOOL keyboard(rdpInput *input, UINT16 flags, UINT8 code) {
    Fixture *f = fixture(input);
    if (code == 0x1e || code == 0x1d || code == 0x5b)
        atomic_fetch_add((flags & KBD_FLAGS_RELEASE) ? &f->key_up : &f->key_down, 1);
    return TRUE;
}
static BOOL mouse(rdpInput *input, UINT16 flags, UINT16 x, UINT16 y) {
    (void)x; (void)y;
    Fixture *f = fixture(input);
    if (flags & PTR_FLAGS_BUTTON1) atomic_fetch_add((flags & PTR_FLAGS_DOWN) ? &f->mouse_down : &f->mouse_up, 1);
    return TRUE;
}
static SECURITY_STATUS hash_password(void *user, const SEC_WINNT_AUTH_IDENTITY *identity,
    const SecBuffer *proof, const BYTE *random, const BYTE *mic, const SecBuffer *mic_value, BYTE *hash) {
    (void)user; (void)proof; (void)random; (void)mic; (void)mic_value;
    static const WCHAR password[] = {'s','y','n','t','h','e','t','i','c','-','t','e','s','t','-','o','n','l','y',0};
    if (identity->Flags & SEC_WINNT_AUTH_IDENTITY_UNICODE)
        return NTOWFv2W(password, (sizeof(password) - 2), identity->User, identity->UserLength * 2,
            identity->Domain, identity->DomainLength * 2, hash) ? SEC_E_OK : SEC_E_INTERNAL_ERROR;
    return NTOWFv2A("synthetic-test-only", 19, (char *)identity->User, identity->UserLength,
        (char *)identity->Domain, identity->DomainLength, hash) ? SEC_E_OK : SEC_E_INTERNAL_ERROR;
}
static BOOL logon(freerdp_peer *peer, const SEC_WINNT_AUTH_IDENTITY *identity, BOOL automatic) {
    (void)identity;
    Fixture *f = ((PeerContext *)peer->context)->fixture;
    if (f->nla) { assert(automatic); atomic_store(&f->authenticated, true); }
    return TRUE;
}
static BOOL post_connect(freerdp_peer *peer) { (void)peer; return TRUE; }
static BOOL activate(freerdp_peer *peer) {
    atomic_store(&((PeerContext *)peer->context)->fixture->activated, true);
    return TRUE;
}
static BOOL paint(freerdp_peer *peer) {
    BYTE pixels[32 * 32 * 3];
    for (size_t i = 0; i < sizeof(pixels); i += 3) { pixels[i] = 0x21; pixels[i+1] = 0x65; pixels[i+2] = 0xc3; }
    BITMAP_DATA rectangle = {0};
    rectangle.destLeft = 0; rectangle.destTop = 0; rectangle.destRight = 31; rectangle.destBottom = 31;
    rectangle.width = 32; rectangle.height = 32; rectangle.bitsPerPixel = 24;
    rectangle.bitmapLength = sizeof(pixels); rectangle.bitmapDataStream = pixels;
    BITMAP_UPDATE update = {.number = 1, .rectangles = &rectangle, .skipCompression = TRUE};
    return peer->context->update->BitmapUpdate(peer->context, &update);
}
static UINT monitor_layout(DispServerContext *context, const DISPLAY_CONTROL_MONITOR_LAYOUT_PDU *pdu) {
    Fixture *f = context->custom;
    assert(pdu->NumMonitors == 1);
    assert(pdu->Monitors[0].DesktopScaleFactor == 200);
    assert(pdu->Monitors[0].DeviceScaleFactor == 100);
    atomic_store(&f->layout_width, pdu->Monitors[0].Width);
    atomic_store(&f->layout_height, pdu->Monitors[0].Height);
    atomic_fetch_add(&f->layouts, 1);
    return CHANNEL_RC_OK;
}
static void *serve(void *arg) {
    Fixture *f = arg;
    int socket = accept(f->listener, NULL, NULL);
    assert(socket >= 0);
    freerdp_peer *peer = freerdp_peer_new(socket); assert(peer);
    peer->ContextSize = sizeof(PeerContext);
    assert(freerdp_peer_context_new(peer));
    ((PeerContext *)peer->context)->fixture = f;
    rdpSettings *s = peer->context->settings;
    rdpPrivateKey *key = freerdp_key_new_from_file_enc(f->key, NULL); assert(key);
    rdpCertificate *cert = freerdp_certificate_new_from_file(f->cert); assert(cert);
    assert(freerdp_settings_set_pointer_len(s, FreeRDP_RdpServerRsaKey, key, 1));
    assert(freerdp_settings_set_pointer_len(s, FreeRDP_RdpServerCertificate, cert, 1));
    assert(freerdp_settings_set_bool(s, FreeRDP_NlaSecurity, f->nla));
    assert(freerdp_settings_set_bool(s, FreeRDP_TlsSecurity, TRUE));
    assert(freerdp_settings_set_bool(s, FreeRDP_RdpSecurity, FALSE));
    assert(freerdp_settings_set_bool(s, FreeRDP_ExtSecurity, FALSE));
    assert(freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32));
    peer->Logon = logon;
    if (f->nla) peer->SspiNtlmHashCallback = hash_password;
    peer->PostConnect = post_connect; peer->Activate = activate;
    peer->context->input->KeyboardEvent = keyboard;
    peer->context->input->MouseEvent = mouse;
    HANDLE vcm = WTSOpenServerA((LPSTR)peer->context); assert(vcm && vcm != INVALID_HANDLE_VALUE);
    DispServerContext *disp = NULL;
    bool sent = false;
    if (peer->Initialize(peer)) {
        double deadline = seconds() + 20;
        while (!atomic_load(&f->stop) && seconds() < deadline) {
            HANDLE handles[32]; DWORD count = peer->GetEventHandles(peer, handles, 32);
            if (!count) break;
            handles[count++] = WTSVirtualChannelManagerGetEventHandle(vcm);
            if (WaitForMultipleObjects(count, handles, FALSE, 25) == WAIT_FAILED) break;
            if (!peer->CheckFileDescriptor(peer) || !WTSVirtualChannelManagerCheckFileDescriptorEx(vcm, atomic_load(&f->activated))) break;
            if (!disp && WTSVirtualChannelManagerGetDrdynvcState(vcm) == DRDYNVC_STATE_READY) {
                disp = disp_server_context_new(vcm); assert(disp);
                disp->custom = f; disp->rdpcontext = peer->context;
                disp->MaxNumMonitors = 1; disp->MaxMonitorAreaFactorA = 8192; disp->MaxMonitorAreaFactorB = 8192;
                disp->DispMonitorLayout = monitor_layout;
                assert(disp->Open(disp) == CHANNEL_RC_OK);
                assert(disp->DisplayControlCaps(disp) == CHANNEL_RC_OK);
            }
            int width = atomic_load(&f->layout_width), height = atomic_load(&f->layout_height);
            if (width > 0 && width != (int)freerdp_settings_get_uint32(s, FreeRDP_DesktopWidth)) {
                atomic_store(&f->activated, false); sent = false;
                assert(freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, (UINT32)width));
                assert(freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, (UINT32)height));
                assert(peer->context->update->DesktopResize(peer->context));
            }
            if (atomic_load(&f->activated) && !sent) { assert(paint(peer)); sent = true; }
        }
    }
    disp_server_context_free(disp); WTSCloseServer(vcm);
    peer->Disconnect(peer); freerdp_peer_context_free(peer); freerdp_peer_free(peer);
    return NULL;
}
static void state(void *user, int value, uint32_t error) {
    Fixture *f = user; if (getenv("MACRDP_FIXTURE_DEBUG")) fprintf(stderr, "state=%d error=%x\n", value, error);
    if (value == 2) atomic_store(&f->connected, true);
    if (value == 0 || value == 3) atomic_store(&f->finished, true);
}
static void frame(void *user) { atomic_store(&((Fixture *)user)->frame, true); }
static void certificate(void *user, const char *host, const char *subject, const char *issuer, const char *fingerprint, bool changed) {
    (void)host; (void)subject; (void)issuer;
    Fixture *f = user; assert(fingerprint && strlen(fingerprint) >= 64);
    atomic_store(&f->changed, changed); atomic_store(&f->certificate, true);
    if (f->decision >= 0) mr_certificate_reply(f->session, f->decision >= 1);
}
static void display(void *user, bool ready) { atomic_store(&((Fixture *)user)->display, ready); }
static void *run(void *user) { mr_session_run(((Fixture *)user)->session); return NULL; }
static void wait_count(atomic_int *value, int count) {
    double until = seconds() + 5;
    while (atomic_load(value) < count && seconds() < until) usleep(1000);
    assert(atomic_load(value) == count);
}
static void test(const char *cert, const char *key, int decision, bool changed) {
    Fixture f = {.cert = cert, .key = key, .decision = decision, .nla = decision >= 3};
    f.listener = socket(AF_INET, SOCK_STREAM, 0); assert(f.listener >= 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK), .sin_port = 0};
    assert(bind(f.listener, (struct sockaddr *)&address, sizeof(address)) == 0);
    socklen_t size = sizeof(address); assert(getsockname(f.listener, (struct sockaddr *)&address, &size) == 0);
    assert(listen(f.listener, 1) == 0);
    rdpCertificate *pinned_certificate = freerdp_certificate_new_from_file(cert); assert(pinned_certificate);
    char *pin = freerdp_certificate_get_fingerprint_by_hash(pinned_certificate, "sha256"); assert(pin);
    MRConfiguration config = {.host = "127.0.0.1", .username = "fixture", .password = decision == 4 ? "incorrect-synthetic-password" : "synthetic-test-only",
        .port = ntohs(address.sin_port), .width = 1600, .height = 1000, .desktop_scale = 200,
        .fingerprint = changed ? "deliberately-wrong-pin" : decision == 2 ? pin : ""};
    MRCallbacks callbacks = {.state = state, .frame = frame, .certificate = certificate, .display = display};
    f.session = mr_session_new(&config, callbacks, &f); assert(f.session);
    free(pin); freerdp_certificate_free(pinned_certificate);
    if (getenv("MACRDP_FIXTURE_DEBUG")) WLog_SetLogLevel(WLog_GetRoot(), WLOG_DEBUG);
    pthread_t server, client; assert(pthread_create(&server, NULL, serve, &f) == 0);
    assert(pthread_create(&client, NULL, run, &f) == 0);
    if (decision != 2) { wait_flag(&f.certificate); assert(atomic_load(&f.changed) == changed); }
    if (decision >= 1 && decision <= 3) {
        wait_flag(&f.connected); wait_flag(&f.frame);
        if (f.nla) assert(atomic_load(&f.authenticated));
        uint32_t w, h, stride;
        size_t count = mr_copy_frame(f.session, NULL, 0, &w, &h, &stride);
        assert(w == 1600 && h == 1000 && stride >= w * 4 && count == (size_t)stride * h);
        BYTE *pixels = malloc(count); assert(pixels);
        assert(mr_copy_frame(f.session, pixels, count, &w, &h, &stride) == count);
        assert(pixels[0] == 0x21 && pixels[1] == 0x65 && pixels[2] == 0xc3); free(pixels);
        assert(!mr_key(f.session, 0x1e, true, false));
        mr_input_enable(f.session, true);
        assert(mr_key(f.session, 0x1e, true, false));
        assert(mr_key(f.session, 0x1d, true, false));
        assert(mr_key(f.session, 0x15b, true, false));
        assert(mr_pointer(f.session, PTR_FLAGS_DOWN | PTR_FLAGS_BUTTON1, 100, 200));
        wait_count(&f.key_down, 3); wait_count(&f.mouse_down, 1);
        mr_input_enable(f.session, false);
        wait_count(&f.key_up, 3); wait_count(&f.mouse_up, 1);
        assert(!mr_key(f.session, 0x1e, true, false));
        assert(atomic_load(&f.connected) && !atomic_load(&f.finished));
        mr_input_enable(f.session, true);
        assert(mr_key(f.session, 0x1e, true, false)); assert(mr_key(f.session, 0x1e, false, false));
        wait_count(&f.key_down, 4); wait_count(&f.key_up, 4);
        wait_flag(&f.display);
        mr_resize(f.session, 1800, 1200, 200);
        double until = seconds() + 8;
        do {
            usleep(1000); (void)mr_copy_frame(f.session, NULL, 0, &w, &h, &stride);
        } while ((w != 1800 || h != 1200) && seconds() < until);
        assert(w == 1800 && h == 1200 && atomic_load(&f.layouts) >= 1);
    }
    if (decision == 4) { wait_flag(&f.finished); assert(!atomic_load(&f.authenticated)); }
    double began = seconds(); mr_session_cancel(f.session);
    assert(pthread_join(client, NULL) == 0); assert(seconds() - began < 2);
    atomic_store(&f.stop, true); assert(pthread_join(server, NULL) == 0);
    if (decision < 1 || decision > 3) assert(!atomic_load(&f.connected));
    if (decision == 2) assert(!atomic_load(&f.certificate));
    mr_session_free(f.session); close(f.listener);
    printf("PASS real TLS/RDP fixture: decision=%d changed-pin=%d NLA=%d authenticated=%d%s\n", decision, changed, f.nla, atomic_load(&f.authenticated),
        (decision >= 1 && decision <= 3) ? ", Retina frame pixels, dynamic resize, key/mouse delivery, release and resume without disconnect" : ", connection blocked/cancelled");
}
int main(int argc, char **argv) {
    assert(WTSRegisterWtsApiFunctionTable(FreeRDP_InitWtsApi()));
    if (argc == 3 && strcmp(argv[1], "--probe") == 0) {
        Fixture f = {.decision = 0};
        MRConfiguration config = {.host = argv[2], .port = 3389, .width = 1600, .height = 1000, .desktop_scale = 200};
        MRCallbacks callbacks = {.state = state, .certificate = certificate};
        f.session = mr_session_new(&config, callbacks, &f); assert(f.session);
        pthread_t client; assert(pthread_create(&client, NULL, run, &f) == 0);
        double until = seconds() + 12;
        while (!atomic_load(&f.finished) && seconds() < until) usleep(1000);
        mr_session_cancel(f.session); assert(pthread_join(client, NULL) == 0);
        printf("Windows host protocol probe: certificate-reached=%s; no certificate accepted or credentials supplied; error=0x%x\n", atomic_load(&f.certificate) ? "yes" : "no", mr_last_error(f.session));
        bool reached = atomic_load(&f.certificate); mr_session_free(f.session); return reached ? 0 : 1;
    }
    assert(argc == 3);
    test(argv[1], argv[2], 0, false);
    test(argv[1], argv[2], -1, false);
    test(argv[1], argv[2], 0, true);
    test(argv[1], argv[2], 1, false);
    test(argv[1], argv[2], 2, false);
    test(argv[1], argv[2], 3, false);
    test(argv[1], argv[2], 4, false);
    return 0;
}
