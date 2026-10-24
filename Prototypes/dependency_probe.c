#include <stdio.h>
#include <freerdp/freerdp.h>
#include <freerdp/version.h>
#include <SDL3/SDL.h>

int main(void)
{
    const int sdl_version = SDL_GetVersion();
    printf("FreeRDP runtime: %s\n", freerdp_get_version_string());
    printf("SDL runtime: %d.%d.%d\n", SDL_VERSIONNUM_MAJOR(sdl_version),
           SDL_VERSIONNUM_MINOR(sdl_version), SDL_VERSIONNUM_MICRO(sdl_version));

    freerdp *instance = freerdp_new();
    if (!instance) {
        fputs("FreeRDP instance allocation failed\n", stderr);
        return 1;
    }
    if (!freerdp_context_new(instance)) {
        freerdp_free(instance);
        fputs("FreeRDP context allocation failed\n", stderr);
        return 1;
    }
    freerdp_context_free(instance);
    freerdp_free(instance);

    printf("SDL video drivers:");
    for (int i = 0; i < SDL_GetNumVideoDrivers(); ++i) {
        printf(" %s", SDL_GetVideoDriver(i));
    }
    printf("\nSDL render drivers:");
    for (int i = 0; i < SDL_GetNumRenderDrivers(); ++i) {
        printf(" %s", SDL_GetRenderDriver(i));
    }
    puts("\nDependency probe passed. No connection or keyboard capture attempted.");
    return 0;
}
