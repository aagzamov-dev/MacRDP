# Setup status — 2026-10-24

## Production release preparation — 0.3.20, 2026-11-06

- The user confirmed the corrected 0.3.19 test build works better and that the desktop
  view is correct on their Windows host, then explicitly requested GitHub publication
  so the original app can update. This confirms that specific visual/connection path;
  it does not mark all physical keyboard, trackpad, audio and Retina matrix rows passed.
- Production 0.3.20 uses the corrected 0.3.19 connection sequence with multiple PCs,
  ordinary Mac-mode input and Command+V, default-enabled speaker/microphone sharing,
  one-time existing-PC migration and per-PC control positions. It retains the original
  app identity, update key/feed and pinned credential helper. The separate Desktop
  test identity remains outside the production update channel.
- SOL's complete release core/native, clipboard-settings, audio and display checks
  passed; core coverage totals 60 tests. Additional signing, input queue, clipboard,
  ten-scenario localhost RDP and synthetic VideoToolbox/software fallback checks passed.
  Astra approved production readiness. Release notes and README now describe current
  capabilities and microphone-on-lock behavior. The publish workflow now also gates
  full native execution, RDP integration, clipboard and native audio checks.
- Microphone cleanup observes app lock, system sleep/display sleep and user-session
  deactivation. Lock-screen-only event delivery without sleep is not verified; release
  notes do not promise it. Security settings now explain the microphone-session exception
  to preserving established connections on app lock.
- Release packages must be rebuilt from the clean reviewed commit matching origin/main,
  preserve the production identity/helper and contain the signed appcast plus ZIP/DMG
  and checksums. Publication and downloaded-asset verification are performed after
  these preparations; this entry does not claim a live Sparkle install/relaunch test.

## Black-session correction — 0.3.19 test, 2026-11-06

- User reported a fully dark remote session in 0.3.18. A real native fixture reproduced
  a startup deadlock: replacing the NSWindow's hosted remote surface cancelled the
  view-owned fullscreen completion while the model's transition flag stayed true.
  This proves a regression mechanism, not the user's exact runtime event trace.
- Removed the pre-connect fullscreen gate, sheet-wait logic, watchdogs and view-owned
  settle callbacks added in 0.3.18. Restored the 0.3.17 connection-before-fullscreen
  sequence. Window delegate enter/exit/failure callbacks now clear transition state
  synchronously before refreshing whichever surface is current, independent of view lifetime.
- Retained accepted-layout caching, authentication-time size forwarding, pre-handle
  resize queues and the protocol worker's latest initial layout snapshot. The correction
  does not revert unrelated audio, microphone, clipboard, per-PC controls or multi-PC work.
- SOL implemented and Astra approved the correction. All 60 core tests and the complete
  native suite passed. The old-path reproduction is recorded in `build/dark-repro-native.log`;
  corrective coverage includes actual native view replacement/reattachment and synchronous
  fullscreen completion in `build/dark-fix-native.log`.
- Built **MACRDP TEST 0.3.19** and verified its deep signature. After a read-only process
  check confirmed the Desktop test app had closed, replaced that copy and retained 0.3.18
  under `build/previous-desktop-macrdp-test-0.3.18.app`. No app was stopped/restarted by
  the agent and the original app was not changed. Actual remote visual recovery still
  requires a connection with the user's Windows host.

## Initial Retina size and fullscreen timing — 0.3.18 test, 2026-11-06

- Fixed concrete lost-layout paths: authentication-stage updates were ignored after
  being cached by the view, and resize calls before native handle creation were lost.
  Geometry is now cached only after acceptance, retained before transport creation,
  forwarded during sign-in and rechecked on connection/display-capability events.
- Fullscreen startup waits for sheet dismissal, native presentation and settled view
  layout before starting RDP. New transitions cancel stale layout callbacks. Explicit
  fullscreen failure falls back to settled windowed geometry; a bounded watchdog handles
  ignored requests but does not time out an animation that has actually started.
- The protocol worker applies the latest queued width/height/Windows scale to initial
  FreeRDP settings before connecting. This avoids relying on display-control support
  to repair an outdated initial size. DeviceScaleFactor remains 100; backing geometry,
  Windows scaling and local image fitting remain separate.
- SOL implemented Swift changes and Astra approved the complete review. All 60 core
  tests, full native regressions, input queue and display-update tests passed. The real
  localhost RDP suite passed ten scenarios, including authentication-time resize bursts
  and an initial 3024×1898 frame on a host with no display-control channel. Deterministic
  tests cover scale-only changes, newer requests during a send and channel reopen.
- Built signed **MACRDP TEST 0.3.18**, verified the Desktop copy's deep signature,
  version, test identity, microphone usage text and disabled updater. Previous 0.3.17
  is kept under `build/previous-desktop-macrdp-test-0.3.17.app`. The test app was inactive
  and was not launched. The original app was not replaced, terminated or relaunched.
- Actual native Space animation, repeated connections to the user's Windows host,
  remote Windows DPI behavior and visual sharpness remain manual acceptance checks;
  the implementation does not claim every host/application honors requested DPI.

## Enabled audio defaults and per-PC controls — 0.3.17 test, 2026-11-06

- New PCs default speaker playback and microphone sharing to enabled. At first launch,
  existing PCs are enabled once using `enabledAudioDefaultsV1`, with the profile save
  preceding the marker. Later opt-outs persist. Session children do not rerun migration.
  The test variant excludes an inherited original-app migration marker, so its migration
  saves in the test preference domain without changing original preferences.
- Added optional typed per-PC session control positions, with **Use app setting** for
  inheritance. The PC editor and live controls both support all six positions; live
  changes persist immediately using the latest profile and preserve unrelated edits.
  Global Settings changes affect only sessions without overrides. Unknown saved values
  fall back to the app setting instead of making profiles unreadable.
- SOL implemented and Astra approved the changes. All 60 core tests and the full native
  suite passed, including one-time migration/later opt-outs, independent overrides,
  global fallback, persistence, clipboard, permission and lifecycle regressions. The
  generated compact session controls preview was inspected; the new picker fits.
- Built and signed **MACRDP TEST 0.3.17** and replaced the inactive Desktop copy after
  verifying its deep signature, version, separate identity and microphone usage text.
  Version 0.3.16 is retained under `build/previous-desktop-macrdp-test-0.3.16.app`.
  Only the original Applications app was running; it was not replaced, relaunched or
  terminated. The test app was not launched, no actual profiles migrated during this
  work, and no microphone accessed. Live Windows audio/input acceptance remains pending.

## Native Mac audio and microphone — 0.3.16 test, 2026-11-06

- Added default-off per-PC microphone redirection with a purpose string and public
  AVFoundation authorization. Permission is requested only on an opted-in connection;
  denied/restricted access gives recovery instructions, and cancelled/stale permission
  results cannot start transport. Permission is checked again before transport creation.
- Speaker playback and microphone capture are independent and explicitly select FreeRDP's
  native Mac rdpsnd/audin backends. A pinned patch adds mono/stereo signed 16-bit PCM input
  and rejects unsupported sample widths/invalid format geometry before queue allocation.
  The dependency build applies the patch idempotently and bundles it with upstream notices.
- App lock and system lock/sleep disconnect actual/pending microphone-enabled sessions,
  even after a profile edit; non-microphone sessions remain connected. Ordinary focus
  switching does not stop calls. No private plugin structs or global permission edits are used.
- SOL implemented Swift permission/UI/lifecycle changes; Astra approved Swift and bridge/
  backend review. 58 core tests, full native smoke/permission regressions, independent
  audio config/addin checks, hardware-free PCM format tests, input queue, clipboard,
  display-update and eight localhost RDP scenarios passed. The packaged native library's
  executable code matches the rebuilt backend; an isolated test resolved the actual bundled
  input/output addins without opening devices. Final diff and shell syntax checks passed.
- Built signed **MACRDP TEST 0.3.16**, verified its identity/version, microphone usage text,
  disabled updater and deep signature, then replaced the Desktop 0.3.15 copy. The previous
  copy is retained under `build/previous-desktop-macrdp-test-0.3.15.app`. Original app,
  credentials and running sessions were not accessed or changed; the test app was not launched.
- Real speaker playback, microphone hardware capture, Windows recording redirection, device
  routing and call quality remain NOT TESTED. Windows host policy must permit redirection.

## Multiple PCs and ordinary Mac-mode control — 0.3.15 test, 2026-11-06

- Each PC has an independent session model, native window, credential lookup, transport,
  reconnect state and focus/input ownership. Opening the same active PC reuses its window.
  Workspace settings and credential access remain shared; lock and quit clean up every session.
- Mac mode permits focused remote typing, clicking, dragging and scrolling without exclusive
  capture. Command shortcuts and macOS desktop navigation remain local. Command+V pastes
  Mac clipboard text into the focused PC without changing modes, respecting per-PC permission.
  Background session clipboard notifications cannot overwrite the Mac clipboard.
- SOL implemented the changes; Astra reviewed the architecture and final source. 58 core tests,
  complete native smoke tests, doctor/dependency probe, input queue, clipboard and display-update
  tests passed. The real localhost RDP suite passed its seven existing cases plus two concurrent
  sessions with isolated input, held-key/button cleanup, independent disconnect and surviving
  session input/resize. FreeRDP 3.32.2 and Swift 6.4 were checked.
- Built and signed **MACRDP TEST 0.3.15**, bundled its native dependencies and verified the
  Desktop copy's signature. Separate identity `uz.macrdp.testshared` uses original preferences
  as fallback and the existing Keychain service via a dedicated validated helper; capture
  verification must be completed for this app identity. See [data sharing](RELEASING.md).
- The test app was not launched and the original running app was not replaced or terminated.
  Real Windows clipboard paste, physical keyboard/trackpad behavior and actual Retina quality
  across two remote Windows hosts remain manual acceptance checks.

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

## Session controls and installer correction — 0.2.3

- Added an outside-click dismissal layer that consumes the dismissal click, compact Mac/Windows control icons with status help, and always-visible Previous/Next Windows desktop buttons.
- Moved Accessibility status, Open Accessibility, Check permission, keyboard test entry and Restart MacRDP to the first Settings section. The existing guarded test flow and session restart confirmation are reused.
- Removed the local-certificate signature from the DMG container. The app and Sparkle signatures and credential helper remain unchanged in identity. Apple requires Developer ID Application signing for signed DMGs.
- 44 core tests and native smoke checks passed; Settings and compact session previews were inspected. Release build and DMG checksum verification passed. The local 0.2.3 installer is prepared, not published. Physical outside-click interaction, live Windows desktop changes and first-download Gatekeeper behavior remain manual checks; local verification does not establish those outcomes.

## Session close and Settings routing — 0.2.4

- Explicit disconnect immediately closes the session window and returns to the workspace; terminal connection events also close it. Closing a session window disconnects, while closing the main workspace still hides to the menu bar. Fullscreen state and window references are cleared, including when disconnecting before transport creation.
- Replaced the empty standard Settings command with the real app settings action. Accessibility is the first explicit settings section, with permission status/open/check/test and restart; keyboard/gesture options have a separate selector. Settings displays the running bundle version.
- No-transport disconnect now resumes pending update installation. Sparkle relaunch preparation releases input, shuts down the session and closes its window before exit.
- Native checks passed for close/disconnect cleanup, repeated disconnect, deferred installation exactly once, relaunch preparation and Settings routing. The native fixture now uses the same non-auto-released window ownership as the app. These checks do not establish a real fullscreen Space animation or complete live Sparkle replacement/relaunch; those remain manual acceptance checks.

## Toolbar interaction — 0.2.5

- Added a shared native SwiftUI button style for the session arrows and control menu. The content shape covers the entire rectangular target, including padding; arrows now have a 44 × 40 point minimum target.
- Presses show an accent fill, border and subtle scale animation. Open controls retain a selected tint. Disabled controls dim, Reduce Motion removes scaling/animation, and no sound is added.
- Native smoke checks passed and the compact toolbar preview was inspected. Physical padding clicks and press feedback still need user acceptance on the installed build.

## Settings and termination — 0.2.6

- Settings has separate Accessibility, Keyboard, Security and Updates sections. Update UI stays inside Settings using Sparkle 2.10.0's SPUUserDriver callbacks; the signed feed/archive/installer path is unchanged.
- Replaced launch-before-quit restart with a bounded waiter that opens the app only after the original PID exits. Explicit application termination dismisses local sheets, closes the session and performs idempotent input/transport shutdown. Update installation prepares termination before requesting relaunch.
- Native subprocess tests passed for app exit with an attached sheet and reopening only after a dummy parent exits. Inline update state tests cover progress, cancellation, one-shot install and error acknowledgements. These tests do not claim a complete real Sparkle replacement/relaunch of the user's installed app.

- Release-gate diagnosis reproduced the actual macOS quit rejection outside the sandbox: terminate returned without exiting while a sheet prevented termination. Local SwiftUI sheets now set NSWindow.preventsApplicationTerminationWhenModal to false via their attached view. The regression fixture lays out a real hosted sheet before asserting this policy and requesting process termination. Earlier sandbox-only success was not sufficient evidence.

## Windows → Mac text clipboard — unreleased

- Added default-enabled, persisted **Settings → Session → Clipboard** sharing toggle. Changes apply to new Windows copies during an existing session.
- FreeRDP 3.32.2's cliprdr channel imports CF_UNICODETEXT only. Local clipboard/file transfer is disabled by the feature mask, no Mac pasteboard reader is installed, and clipboard text is never logged. UTF-16 validation, a 16 MiB response limit, newline conversion and stale-response/settings/session guards protect delivery.
- Code-only validation passed: 47 core tests, mocked clipboard negotiation/data/lifecycle tests, settings persistence/delivery tests with an injected writer, existing input queue/cleanup tests, and an unsigned Debug Xcode build (compiler plugin sandbox disabled in the build invocation).
- No app launch, real pasteboard access, live Windows session, release packaging, installation or publication was performed. Physical Windows → Mac copy/paste remains unverified.

## Keep awake while connected — unreleased

- Added a default-on, persisted Session → Power setting using the public ProcessInfo activity API, with no timer or global power preference changes. Saving the setting updates an active session; failure, disconnection and shutdown release the activity.
- Unsigned Debug Xcode build and native smoke tests passed, including default/persistence, live toggle, repeated connected events, focus preservation, terminal cleanup, reconnect and late state changes after shutdown. Actual idle-sleep/display behavior during a live Windows session remains a manual check.

## 0.3.0 optimization and feature pass — 2026-10-28

- Added bounded dirty-region Metal presentation, asynchronous frame preparation and shader setup, idle/hidden display-link suspension, and CoreGraphics fallback. Kept the existing icon-only toolbar.
- Added visible connection-failure recovery, cancellable bounded retries for established saved-credential sessions, search/favorites/recents/duplicate, window geometry restoration, per-PC overrides, fixed resolution and actual-pixel panning, explicit outbound clipboard paste, Windows security/task actions, audio playback and native text/IME mode.
- 53 core tests passed. Mocked bridge tests passed for input ordering/cleanup, clipboard policy, accumulated frame regions, resize/buffer capacity, Unicode input and clipboard acknowledgement/cancellation. ASan/UBSan and C static analysis passed for the bridge update tests. Headless model tests passed for per-PC options, persistence, failure visibility and retry cancellation, using injected permission and clipboard handlers with keep-awake disabled; no app, window or network session was started.
- Native smoke test executable was compiled only, using `scripts/test-native.sh --build-only`. The UI subprocess tests were not run. Debug and signed Release builds passed. The self-contained 0.3.0 (build 9) manual-test app bundles 32 native libraries; signature and archive checks are recorded with the artifact.
- Existing signed credential helper remains unchanged. No app launch, Windows connection, real pasteboard read/write, saved Windows password access, installation, push or publication was performed. Live FPS, GPU rendering, hardware decoding, audio/IME interoperability and manual acceptance remain unverified. The optional offline Metal compiler is unavailable; runtime shader compilation has a CoreGraphics fallback.

### 0.3.1 test build: Mac account unlock and PIN recovery

Implemented native LocalAuthentication unlock and PIN reset with Mac password fallback, preserving saved credentials and separate test identity. Authentication is cancelled on locking/shutdown and stale results cannot reopen the workspace. Verified with 56 core tests and injected headless model checks; actual OS dialogs and session behavior remain untested as requested. Packaging now removes its temporary source/build copy after completion.

### 0.3.3 test build: floating controls layering

Addressed the reported controls disappearing after connection by creating the remote NSView's backing layer during initialization rather than changing its layer backing when Metal starts. Clip the renderer to the desktop view and give the SwiftUI controls a separate compositing group above the desktop. Controls remain unconditional across connection phases; release icon, positioning, input actions and pixel geometry are unchanged. Release build and static checks only: the app was not launched and post-connection visibility still requires the user's manual verification.

### 0.3.5 test build

Added per-PC macOS VPN selection and readiness gating with ownership-limited, non-forced cleanup. Read-only SystemConfiguration discovery confirmed two installed Kerio profiles; live connection compatibility remains untested at the user's request. Added full-screen Dock presentation handling and a one-time default-on migration, preserving subsequent opt-out choices. Core and injected headless tests cover failure/cancellation and existing-VPN preservation; no app launch or VPN start/stop performed.

### 0.3.7 test build

Replaced generic VPN-start calls for Kerio with an Accessibility menu adapter using the exact selected profile. Existing macOS status polling and app-owned cleanup remain; normal termination now waits for asynchronous VPN cleanup. Requires the running Kerio status icon and Accessibility for MacRDP. Mock/headless behavior checked and native target compiled without execution; actual menu integration remains unverified because no VPN or app was run.


### 0.3.8: remove VPN automation

Removed native VPN start/stop, Kerio menu Accessibility code, automatic-disconnect setting and asynchronous quit cleanup. Retained profile selection and cancellable, read-only waiting for manual VPN connection. Revised Dock eligibility to follow the active Windows session rather than keyboard-capture state, and reassert hiding if overwritten. 57 core tests and headless passive-wait/Dock checks passed. No app or VPN was run.
