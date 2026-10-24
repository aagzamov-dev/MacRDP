# Setup status — 2026-10-24

## Input, menu bar, presentation and updater implementation

- Windows input intent now defaults on per session, survives temporary focus/Space changes, and remains separate from an explicit Mac selection. Four-finger release waits for departure before recapture. Physical gesture and Windows shortcut acceptance is still pending.
- A separate full-screen session window hides the main PC list, with a click-only Controls panel and persistent menu-bar controls. Closing windows preserves the session; Quit ends it.
- Frame preparation is off the main thread, bridge snapshot updates copy dirty regions, presentation uses a display link with visibility gating, and pointer moves coalesce without crossing ordered input. Presented FPS is counted; no real-Windows FPS/latency claim is made.
- Added Sparkle 2.10.0, signed GitHub appcasts/archives, Updates settings, and local packaging/draft-release scripts. Generated a dedicated update key in Keychain; no private key is in the repository. No release has been published. Updates do not require an Apple Developer account; the app now uses persistent self-signing and a fixed credential helper; it is not notarized.
- 37 core tests, native model/menu/close/update guards and UI rendering, dirty-region/pointer queue tests, and seven localhost RDP scenarios passed during implementation. Debug/Release builds, C static analysis, sanitizer runs and packaged-app/archive/feed signature validation passed; a deliberately modified update feed was rejected. Actual trackpad/Space interactions, real Windows visuals/performance, and two-version update installation remain manual acceptance work.

## Current native RDP client

The local-only prototype has been replaced by a working FreeRDP-backed client implementation. See [CLIENT.md](CLIENT.md) for the user flow, architecture, verification and boundaries. The historical entries below preserve earlier findings and do not override this update.

- Implemented saved PC list and add/edit/delete, Keychain passwords, startup/manual PIN lock, full screen, connect/cancel/disconnect/retry, explicit per-host certificate trust, Retina geometry/cursor rendering, dynamic display control, native keyboard/mouse/scrolling, configurable shortcut and gesture mappings.
- Mac input, Space changes, browsing PCs and manual app lock preserve an established connection. Initial exclusive capture remains gated by local release checks and a timed first captured-release check; physical interception is still unverified.
- Debug and Release builds, signature verification, C static analysis (zero findings), doctor/probe, 32 core tests, native view/PC/credential lifecycle tests, deterministic input queue tests and real TLS/RDP peer integration pass. Address/undefined-behavior sanitizer runs pass. Real peer tests cover CredSSP/NLA login and wrong-password rejection with synthetic credentials, pixel values, key/button delivery and cleanup, input resume without disconnect, certificate decisions/pins and dynamic 1600×1000 → 1800×1200 resizing.
- The documented Windows VPN host's RDP certificate was reached and deliberately rejected without supplying credentials. No authenticated Windows login, visible Windows actions, visual Retina acceptance or performance parity is claimed.
- Application deployment is macOS 27.0+ / Apple Silicon, matching the installed dylibs, with Homebrew development linkage. Portable packaging/notarization and hardware decoding remain separate work.
- The implementation and tests used no screen control, did not open the app, and did not read the user's saved passwords or change permissions, VPN configuration or global input settings.

### Session controls menu validation (2026-10-24)

- Replaced hover/timed reveal with an explicit Controls button and a compact panel; the Mac/Windows picker label no longer compresses vertically.
- Opening the panel releases remote input and prevents recapture until closed, preserving the selected mode. A separate release button remains visible during first-use verification.
- Debug and Release builds, 37 core tests, and native smoke tests pass. Native previews at 640×400 verify light/dark layouts and a long PC name. Native checks cover panel input suspension and preservation of explicit Mac mode. Physical interaction with a live Windows session remains untested for this change.

### Keyboard setup, permissions and Dock icon (2026-10-24)

- Added one Keyboard setup sheet from Settings, session controls and the menu bar. It provides Accessibility open/check actions, automatic permission refresh, scoped local escape/button verification, and an explicit timed first-capture test.
- The compact session button now shows actual capture status and actionable permission/setup/failure reasons. Ordinary input can upgrade after prerequisites become ready; that transition releases previously held remote input. Active status requires a running, enabled event tap.
- Added optional restart using the current app bundle, a connected-session confirmation, and a recoverable launch error. The Dock explicitly uses the bundled AppIcon.icns artwork; the asset and bundle icon metadata remain intact.
- Debug and Release builds, all 37 core tests, expanded native smoke tests, strict app-signature verification and bundled icon metadata checks pass.
- Automated coverage uses injected permission/restart operations without touching real permissions or launching another app. Actual Accessibility grant, process relaunch, Dock appearance and physical shortcut interception remain manual checks.

### Persistent credentials, modifier mapping and installer (2026-10-24)

- Created a persistent self-signed code-signing identity in login Keychain and pinned its public certificate. Applied user-domain trust for this certificate’s code-signing policy only. Existing passwords, VPN trust and TLS policies were not changed.
- Empirical correction: two freshly signed binaries with identical certificate-based requirements still could not share a synthetic Keychain item noninteractively on this macOS. Stable signing alone is insufficient for this build’s Keychain behavior.
- Added a fixed signed credential helper with bidirectional caller/helper signature verification, existing service/account names, private-pipe messages and pinned source/binary hashes. The production helper is copied unchanged across releases. A two-version app test using the unchanged helper passed with Keychain interaction disabled; an untrusted caller was rejected. Tests used a separate synthetic Keychain service and cleaned their own item; real saved passwords were not read or changed.
- Added persisted Command/Control/Option/Shift selectors, disabled-key support, a Command→Ctrl / Control→Windows preset, left/right preservation, shared-modifier reference tracking and release-before-remapping. Release shortcuts and Force Quit remain physical.
- Three-finger detection now handles partial/empty lifts, a lower horizontal threshold, four-finger precedence and cancellation. Desktop actions use fixed Ctrl+Windows+arrows independently of mappings, with manual Desktops actions and gesture feedback for diagnosis. Actual physical three-finger routing still needs a user trackpad check; macOS-owned gestures cannot be intercepted with these APIs.
- 44 core tests, native settings/credential lifecycle/permission checks, input queue tests and seven localhost RDP scenarios pass. Final installer verification also passed: read-only mount, app and helper signatures, unchanged helper bytes, Applications shortcut, installation instructions, checksums, signed update archive and signed appcast. Prepared a self-contained local 0.2.1 release with 32 bundled native libraries, signed update ZIP/appcast and a signed drag-to-Applications DMG. No GitHub release was published.

## Historical preparation and prototype findings

## Completed preparation

- Created a new project at `/Users/user/Desktop/Projects/MacRDP` with a development prompt, detailed requirements, keyboard/performance test plans, project rules, a local development skill, and source/test directories.
- Installed Homebrew FreeRDP **3.32.2**, CMake **4.4.4**, Ninja **1.13.2**, and pkgconf **3.0.10**.
- SDL3 **3.4.18** and SDL3_ttf **3.2.2** are installed; FreeRDP brought its runtime dependencies, including FFmpeg **9.0.2_1** and OpenSSL **4.0.3**.
- Existing Xcode **27.0 (27A266a)** and Swift **6.4** were usable. This Mac reports macOS **27.0.1 (26A434)**, arm64.
- Compiled and ran the included native dependency probe. FreeRDP context allocation/free succeeded. It reports the Cocoa video driver and Metal among available SDL render drivers. Enumeration does not prove actual GPU rendering or hardware decoding.
- `pkg-config` resolves `freerdp3`, `freerdp-client3`, and `winpr3` as **3.32.2**, and `sdl3` as **3.4.18**.
- Saved installed client help/build configuration and a sanitized doctor report in `docs/research/`.
- A TCP reachability check to **10.10.40.75:3389 succeeded** during preparation. This is not authentication or a newly tested RDP session.
- Existing Microsoft Windows App reports **11.4.4**, available as the comparison client.

## Important findings

`sdl-freerdp /buildconfig` reports `WITH_CLIENT_SDL3=ON`, `WITH_CLIENT_MAC=OFF`, `WITH_GFX_H264=ON`, `WITH_FFMPEG=ON`, and **`WITH_FFMPEG_HWACCEL=OFF`**. The legacy upstream Mac client is not included in this bottle. The SDL client is available without installing XQuartz.

SDL 3.4.18 source conditionally implements keyboard grab with private CGS hotkey functions. An `nm -u` check of the installed SDL dylib found no references to those functions. Do not infer that Command+Tab capture works. The public-API prototype and physical-key tests remain mandatory.

Homebrew upgraded several shared dependencies required by FreeRDP, including SDL, FFmpeg, font/X11 support libraries and CA certificates. OpenSSL 4 was linked and Homebrew unlinked the OpenSSL 3 command/header symlinks; the older keg was not deliberately removed. Installation used `HOMEBREW_NO_INSTALL_CLEANUP=1`. No general `brew upgrade` or cleanup was run. The old SDL3 3.4.16 keg remains, while pkg-config and runtime select 3.4.18.

No Kerio settings, server certificates, Windows policies, saved credentials, global shortcuts or trackpad preferences were changed for this preparation. No keyboard-capture permissions were requested.

## Still to implement and verify

- Native `.app`/Xcode target, stable signing identity and normal permission flow.
- Public-API local capture and the **Control+Option+Command+G** release shortcut.
- Actual remote Win+Tab, Alt+Tab and Control+Tab delivery through the custom app.
- FreeRDP bridge, required Retina/DPI rendering, session lifecycle and native connection UI. Follow `RETINA-DISPLAY.md` for geometry, cursor mapping and acceptance tests.
- Three-/four-finger gesture feasibility.
- Windows App comparison, hardware decoder experiment if needed, and release packaging.

The custom app was not implemented during the original setup. The later native prototype update below supersedes application setup items only; no remote login or performance benchmark has been performed.

## Commands

```sh
cd /Users/user/Desktop/Projects/MacRDP
./scripts/doctor.sh
./scripts/build-probe.sh
```

Optional upstream connection baseline, when ready to reconnect the Windows session:

```sh
./scripts/run-baseline.sh 10.10.40.75 'DESKTOP-KPE9ERR\Abdurashid'
```

That account spelling is a suggestion to verify. Enter the password only at the client prompt. The script keeps normal certificate checks, NLA, and a windowed display, disables keyboard grab and clipboard, and isolates its configuration under ignored `build/baseline-config/`. Its launch arguments were checked against installed help; an interactive connection through this script has not been tested.

The upstream SDL shortcuts documented by this installed build use **right Shift** as their modifier: right Shift+Return toggles full screen; right Shift+M minimizes; right Shift+D disconnects; right Shift+G toggles grab. These are upstream controls, separate from the custom app's future release shortcut. Do not use the grab toggle as evidence of system-shortcut capture.

`Brewfile` installs current formula versions, not an immutable lock. `docs/research/dependencies.json` records observed versions and the FreeRDP source checksum. Before implementing against a newer library, inspect its API/build changes.

## Final validation

- `scripts/bootstrap.sh` completed successfully from the final Desktop project location; all five Brewfile entries were satisfied.
- `scripts/doctor.sh` and the CMake/Ninja build completed; the dependency probe ran successfully from the final project path.
- `otool -L` confirms the probe links FreeRDP client/core, WinPR, SDL3, and the macOS system runtime.
- All four shell scripts passed Bash syntax checks. The baseline launcher's help path was tested; its interactive connection path was not run.
- The project skill passed the supplied `quick_validate.py` validator. PyYAML was installed only in a temporary validation virtual environment outside this project.
- All relative Markdown file links resolve.
- A local Git repository was initialized on `main`; no commit, remote, or publication was created. Build/configuration outputs are ignored.

## Retina requirement update — 2026-10-24

The user made Windows App-like Retina optimization mandatory. Updated the new-chat prompt, requirements, project instructions, skill, keyboard/performance plans, and the new `RETINA-DISPLAY.md` specification. This is a documentation change; no application code, libraries, display settings or runtime results changed. Retina remains unimplemented and untested.

## Native prototype update — 2026-10-24

- Added the native Xcode app, SwiftUI/AppKit interface, public session-tap implementation, release rehearsal gate, visible Release control, ten-second safety timeout, focus/lifecycle cleanup and Force Quit pass-through.
- Added four-finger release and three-finger Windows desktop gesture recognition. Real delivery remains untested and macOS can consume system gestures.
- Added a 4–12 digit app PIN (minimum four digits per the user's correction), locked on process startup and manually lockable. Saved PC passwords use Keychain. No user PIN/password was created by the development agent.
- Environment/dependency probe, native app build, 18 core tests and native view/gate smoke tests passed. The first-run locked screen, successful user PIN setup, unlocked workspace and rehearsal timeout were observed through the native UI.
- No actual exclusive keyboard/gesture test or Windows result is claimed. The RDP bridge, remote Retina renderer and performance comparisons remain pending.
- User reported successful shortcut rehearsal. A separate UI-automation rehearsal plus toolbar Release verified the UI gate and enabled Capture; that synthetic check is not evidence of exclusive system-key routing.
- The first capture attempt after user-granted permission failed safely at startup. Updated startup to set current eligibility atomically with arming and added a specific unavailable-tap failure check to the native smoke test. The updated app rebuilt and restarted locked with its existing PIN record recognized; successful exclusive capture is still pending runtime retest.
- A subsequent automated capture attempt observed the tap immediately disable. Updated the tap lifecycle to wait for run-loop readiness, removed AppKit queries from the callback, and moved tap control/health queries outside the state lock. Native build/smoke checks pass. Physical capture retest on this final build remains pending; previous failures are not recorded as passes.
- See [PROTOTYPE.md](PROTOTYPE.md) for launch instructions, architecture, research and exact pass/not-tested boundaries. The original keyboard and Retina manual acceptance matrices remain NOT TESTED.

## Input toggle clarification — 2026-10-24

- The user clarified that the shortcut must toggle Mac/Windows keyboard ownership while keeping the app/session window and full screen unchanged. Four-finger movement should preserve normal macOS Space navigation; the session stays open until explicitly closed. This replaces the earlier hide/exit-full-screen release behavior.
- Removed automatic hide/full-screen-exit actions from input release. Added a recorded, persisted keyboard toggle in Settings, shortcut validation, re-verification after binding changes, and key-lift gating before recapture. Added active-Space/visibility checks and Space-change release without altering the window.
- Core behavioral tests now total 24 passing cases. The native smoke test also checks binding persistence and that release retains the session window; generated workspace/settings previews were inspected.
- Physical capture, custom-shortcut round trips and three-/four-finger delivery on this build remain unverified. RDP/Retina rendering are still pending; no actual Windows result is claimed.
