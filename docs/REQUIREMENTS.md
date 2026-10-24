# MacRDP requirements and implementation handoff

Prepared 2026-10-24 for `/Users/user/Desktop/Projects/MacRDP`.

## 1. Outcome and scope

Build a simple native macOS RDP client that connects to an existing Windows RDP host. Its distinguishing feature is predictable keyboard ownership: while the remote surface owns input, ordinary Windows combinations go to Windows; a dependable local escape returns control to the Mac without disconnecting.

The user prioritizes Command+Tab behaving as Windows Win+Tab, reliable exit, native appearance, and responsiveness comparable to Windows App. A small functioning client is more valuable than a broad unfinished clone. The current preparation delivers installed libraries, checks, and this handoff. No working custom app or keyboard-capture result is implied.

First release scope: Apple Silicon, one session at a time, one monitor, direct RDP over the existing VPN, native connection form, full screen, keyboard and pointer input, required Retina rendering with Windows UI scaling, dynamic resolution, clear disconnect/errors, and optional text clipboard after the core input milestone. Start on the installed OS; choose a minimum supported macOS version only after checking the library deployment targets.

Defer accounts/cloud sync, gateways, RemoteApp, multi-monitor, file transfer, drive/USB/printer/smart-card redirection, microphones/cameras, iOS/Windows clients, and elaborate visual themes. Add audio playback after input and display are stable. Do not implement an RDP server or a new VPN.

## 2. Known user environment

| Item | Known information |
|---|---|
| Mac | Apple Silicon arm64; see setup report for actual OS/toolchain |
| Existing VPN | Kerio Control VPN Client; server `baik.uz`; preserve configuration |
| Windows host | `DESKTOP-KPE9ERR` |
| Last known VPN address | `10.10.40.75`, RDP port `3389`; may change |
| Windows Ethernet address | `192.168.1.13`; not the first choice across the VPN |
| Username clue | `Abdurashid` from `C:\Users\Abdurashid`; verify local/domain identity |
| Working comparator | Microsoft's Windows App; user has successfully connected |

The Kerio certificate problem was previously resolved with a user-authorized exception scoped to its server certificate. That exception is unrelated to RDP and must not be copied or widened. Do not ask the user to change the VPN server certificate as part of this project. Do not assume VPN peers always retain the same addresses or share the same address. Check reachability before diagnosing application protocol failures.

Do not extract Windows App credentials or copy VPN configuration into the repository. Ask the user to type Windows credentials into a secure native field. Distinguish Windows account password from a Windows Hello PIN. Local account syntax may be `DESKTOP-KPE9ERR\Abdurashid`; that is a candidate to verify, not a guaranteed account.

## 3. Stack decision

| Layer | Choice | Reason |
|---|---|---|
| RDP engine | FreeRDP 3 + WinPR | Existing native protocol, authentication, channels, and codec implementation |
| Application | Swift with SwiftUI and AppKit | Standard Mac controls; direct access to window/input lifecycle |
| Library boundary | Small C-compatible interface, implemented in C/Objective-C as needed | Keep raw FreeRDP pointers and ownership out of Swift UI |
| Remote surface | Native AppKit view; measured rendering path | No web framebuffer or reactive view update for each frame |
| Baseline client | Installed `sdl-freerdp` with SDL3/Cocoa | Quickly separates server/engine issues from custom application issues |
| Prototype build | CMake + Ninja + pkg-config | Already verifies native library linking |
| Product build | Native Xcode app target with stable bundle ID | Proper app lifecycle, permissions, resources, signing and profiling |

FreeRDP is the chosen engine, not a claim of universal fastest performance. Do not switch to an immature engine or implement RDP to chase an unmeasured speed gain. Compare the FreeRDP baseline to Windows App first, then improve the specific measured bottleneck.

Use standard SwiftUI `Form`, `List`, buttons, toolbar items, settings, alerts, and SF Symbols. AppKit owns the session window and input integration when that is simpler. There is no need for a third-party UI design library. Customization belongs in preferences, not a custom UI framework. A polished native UI does not require rebuilding Microsoft's design.

The prepared CMake target is a dependency probe only. Create the native app target during the first implementation milestone. Keep it in the repository; use a small generation tool only if it actually makes the project easier to maintain.

## 4. Verified library facts and constraints

- Preparation baseline: FreeRDP **3.32.2**, SDL3 **3.4.18**. Installed details are in `SETUP-STATUS.md` and the saved `research/` outputs. Recheck versions if Homebrew changes them.
- The installed client supports SDL3, FFmpeg, and H.264 graphics. It reports **`WITH_FFMPEG_HWACCEL=OFF`**. The baseline therefore cannot establish FFmpeg hardware decode performance. Merely having FFmpeg/VideoToolbox available is not evidence that FreeRDP uses it.
- `SDL_SetWindowKeyboardGrab` is a main-thread API. Its generic documentation does not guarantee every macOS system shortcut. [SDL API documentation](https://wiki.libsdl.org/SDL3/SDL_SetWindowKeyboardGrab).
- SDL 3.4.18's Cocoa implementation calls private CGS hotkey functions only under `SDL_MAC_NO_SANDBOX`; otherwise its keyboard-grab function still returns success. The installed library's undefined-symbol inspection found no references to those CGS functions. This is build evidence, not a physical keyboard test. [Versioned Cocoa source](https://github.com/libsdl-org/SDL/blob/release-3.4.18/src/video/cocoa/SDL_cocoakeyboard.m).
- FreeRDP's SDL client is a useful reference for lifecycle, input, and updates, not a native SwiftUI toolkit. Inspect source matching the installed version. [FreeRDP SDL3 client](https://github.com/FreeRDP/FreeRDP/tree/3.32.2/client/SDL/SDL3).

Keep baseline testing windowed with keyboard grab disabled. Product capture must use a separate, measured public-API implementation. Do not ship the private SDL CGS path as the solution, and do not interpret a successful flag assignment as a successful shortcut test.

## 5. Keyboard ownership: required behavior

The default physical mapping is Command → Windows key, Option → Alt, Control → Control, Shift → Shift. Preserve left/right modifiers, extended scan codes, and AltGr where the layout requires it. Use physical scan codes for combinations. Text composition/IME is a separate mode/path, not a reason to convert every key into Unicode.

| Mac input while captured | Required remote result |
|---|---|
| Command+Tab | Windows Win+Tab / Task View |
| Option+Tab | Windows Alt+Tab |
| Control+Tab / Control+Shift+Tab | Next/previous tab in the focused Windows app |
| Command+R, Command+E, Command+D | Windows Run, Explorer, show desktop |
| Control+C/V/X/A/Z | Windows edit shortcuts |
| Control+Command+Left/Right | Switch Windows virtual desktops, when available |
| Control+Option+Command+G | Toggle Mac/Windows keyboard ownership in place; consume the G action locally |

Do not make Command+C mean Control+C in the first capture mode: it conflicts with physical Windows-key fidelity. A later optional compatibility preset can remap specific chords, with its behavior shown explicitly.

The escape shortcut is configurable, but a valid release binding must always exist. Default **⌃⌥⌘G** avoids relying on function-key settings. Reject a conflicting binding, an unmodified typing key, or the Force Quit chord. Display the active binding in the toolbar and a brief capture-entry overlay.

The shortcut toggles keyboard ownership without hiding, minimizing, closing, disconnecting or exiting full screen. Releasing immediately stops filtering/forwarding, resets remote held keys when the connection permits, and restores the previous presentation options. Pressing the shortcut again while the session surface owns focus captures after the shortcut keys are lifted. Make the shortcut easy to record and change in Settings. Four-finger movement should retain normal macOS desktop/Space navigation with the session window and connection intact; release input when the gesture reaches the app or its active Space/focus changes. Do not programmatically choose a Space or change global gesture settings. These behaviors reflect the user's latest clarification and replace the earlier release-and-hide default.

The release key's modifier prefixes may already have been sent before G completes the chord. Send corresponding remote key-ups and never send the G down/up as a remote action. Wait for the locally held release keys to be lifted before allowing capture again. Do not synthesize those keys into another Mac app.

### Capture state and lifecycle

Represent ownership explicitly: **local**, **arming**, **captured**, **releasing**. Connection state is separate. Capture only when the connection is ready, the session surface is key/frontmost, no local modal/text field owns focus, required permissions are usable, and release handling is armed. Initially require an explicit capture action. Later allow an opt-in automatic capture on entering full screen.

Release on explicit escape, toolbar action, loss of key-window/app focus, minimization, hide, native sheet/dialog, full-screen exit, connection error, disconnect, sleep/session lock, permission loss, tap disable, or shutdown. Regaining focus must not silently recapture after a release.

Track pressed remote keys and mouse buttons. Cleanup must be idempotent and shared by normal and failure exits. Send key-ups while transport is usable; never block local release waiting for the network. If disconnected, clear local state and reconcile on a new session. Do not dereference a freed `rdpInput` during asynchronous cleanup.

Use a single authoritative route per physical event. AppKit handlers plus an event tap plus SDL must not each send the same key. Account for repeat, left/right modifiers, Caps Lock, rapid focus changes, and the macOS behavior of key-up events when Command is held. Keep raw key codes/layout conversion separate from application commands.

### Public-API feasibility prototype

1. Build a small native `.app` with fixed bundle ID and a visible release button. Start in local mode. Provide an optional 10-second automatic release during early testing.
2. Test AppKit handling plus valid `NSApplication.PresentationOptions` that include `disableProcessSwitching` while captured. Apple documents that this suppresses Command+Tab switching; whether events reach the app correctly still requires testing. Snapshot/restore the prior options and respect valid option combinations and full-screen delegate transitions. [Apple API](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct/disableprocessswitching).
3. Where needed, use an active public CoreGraphics **session** event tap to filter keyboard events only in the captured state. Prefer the least privileged working tap; do not require a root HID tap. A global NSEvent monitor cannot suppress events. Check actual tap creation and event delivery. [CoreGraphics event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
4. Keep callbacks short: evaluate escape, update a small state snapshot, enqueue compact input, return. No network calls, modal prompts, unbounded allocation, or expensive logging in the callback. A dedicated run loop can isolate the tap from rendering; use explicit synchronization.
5. On a disabled/failed tap or stale session state, stop interception and return to local mode. A watchdog can detect a stalled worker; it cannot guarantee recovery from every whole-process/OS hang. Preserve macOS Force Quit as the final independent escape.
6. Only after local release tests pass, feed mapped events into the actual RDP session and observe Windows Task View. A local key-counter is insufficient evidence of the complete behavior.

Do not set `disableForceQuit` or `disableSessionTermination`. Power, Touch ID, secure-entry paths, hardware Fn behavior, and OS-reserved shortcuts may remain local or unavailable. Describe exact supported combinations. “Full capture” is a user-facing goal, not permission to promise every key under every OS condition.

### Permissions

Use normal macOS Accessibility/Input Monitoring authorization only when the chosen public API needs it. Check capability first; request through the standard system flow after an explicit capture action. If denied, stay in normal keyboard mode with a precise explanation and a route to System Settings. The user's installation request does not pre-grant TCC permission.

Use a stable app bundle path/identity during development to reduce repeated authorization. Do not grant Terminal or Codex broad keyboard privileges as a substitute for the product's own permissions. Do not modify TCC databases, global system shortcuts, SIP, or the user's security settings. Screen Recording is not intrinsically required to display a received RDP framebuffer. More permissions do not guarantee more shortcut support.

## 6. Trackpad and pointer

Support pointer movement, click/right-click, drag, wheel/precise scrolling, and correct coordinates across Retina scaling and resize. Release remote held buttons on capture exit. Keep an on-screen release control reachable; exclusive pointer confinement is unnecessary initially.

Later investigate public AppKit gesture/touch events while the remote surface is active. Proposed optional mappings: three-finger up → Win+Tab, left/right → Control+Win+Left/Right, down → Win+D. These synthesize Windows commands; they are not native Windows Precision Touchpad pass-through.

Preserve four-finger macOS Space navigation when the user's system configuration permits it. macOS may consume gestures before the application sees them, and assigning three versus four fingers is affected by System Settings. Measure this on the user's trackpad; do not silently change preferences or rely on private MultitouchSupport APIs. If the split cannot work through public APIs, leave those gestures to macOS and keep keyboard/menu escape fully working. Gesture support must not block the first release.

## 7. Session engine and rendering

Keep the initial design small: a native app/session model, an input controller, a thin RDP bridge, and one session view. Add files as needed under `Sources/`; do not create a framework for every callback.

Give each FreeRDP context one lifetime owner. Use the current client initialization, channel loading, settings accessors, callbacks, and event loop from matching headers/source. Do not copy an old FreeRDP 2 example or expose guessed struct layouts to Swift. Serialize connection/input/teardown, signal the worker instead of polling tightly, and never run a blocking connect or decoder on the main thread.

The bridge should expose only lifecycle actions, typed configuration, input events, frame/dirty-region notifications, and sanitized status/error callbacks. Specify buffer ownership and lifetime. UI/certificate/authentication callbacks hop to the main thread without deadlocking the engine. Disconnect must cancel pending authentication and join the worker before freeing resources.

Start with a correct framebuffer path based on FreeRDP's existing decoding/GDI support. Present through a native view; use a reusable Metal texture and simple presentation path when implementing the performant version. A temporary CoreGraphics baseline is acceptable if clearly identified and measured. Avoid allocating a SwiftUI image per frame, base64/JPEG transport inside the app, or copying the full framebuffer repeatedly for every dirty rectangle.

Separate decoded-buffer ownership from rendering; the engine must not mutate a buffer the GPU/UI is reading. Coalesce dirty rectangles, bound pending frames, and prefer recent complete visual state over an ever-growing queue. Do not drop arbitrary RDP protocol updates; coalesce presentation after they are applied. Preserve input order independently of frame presentation. Handle resize/cursor changes and disconnect while a frame is pending.

Enable modern graphics/codec paths supported by both ends, with reliable fallback. Use 1080p for an initial engine sanity check, then treat the user’s actual Retina backing resolution as a primary quality and performance acceptance target. Keep sharp Retina mode as the default, with an explicit lower-resolution preference if desired. Hardware decoding requires a verified FreeRDP/FFmpeg path and possibly a project-local source build. Do not equate a Metal renderer with a hardware video decoder or assume zero-copy output.

### Required Retina behavior

Implement [RETINA-DISPLAY.md](RETINA-DISPLAY.md) as part of the first usable release. It defines backing pixels versus Mac points, Windows DPI negotiation, resize handling, cursor transforms, mixed-density display movement, quality/performance policy, and the acceptance matrix. The local keyboard prototype may be simple; the first remote view must use correct geometry, and release readiness requires Retina verification. Moving a single-session window between displays is in scope even while multi-monitor spanning remains deferred.

## 8. Connection UX and data

Start with a PC form containing name, host, port, username/domain, Connect, and a secure password field. Save non-secret connection settings locally; save a password to Keychain only when the user opts in. Distinguish connecting, authenticating, connected, reconnecting, disconnected, and failed states. Provide cancel and actionable errors such as unreachable host, authentication rejected, certificate mismatch, or unsupported feature.

Keep NLA and TLS verification. For a self-signed/untrusted RDP certificate, show identity/fingerprint details and require an explicit per-host trust decision; verify through the existing host/admin when needed. Persist a host-specific pin only after that decision, and stop on an unexpected change. Do not add `/cert:ignore`, downgrade to legacy RDP security, or install a global trust exception to make a demo connect. The existing Kerio exception does not authenticate the Windows host.

The full-screen toolbar should show host, connection status, capture status, release shortcut, Release, Disconnect, and settings access. Reveal it on pointer movement near the edge; do not put a permanent overlay over remote controls. Release input before a local dialog receives keys. Standard appearance, light/dark mode, keyboard accessibility, and readable controls are enough for the first build.

Preferences after the first milestone: capture mode, release shortcut/action, modifier preset, resolution/scale, clipboard opt-in, audio playback, and experimental gesture mappings. Keep advanced settings behind a compact section with sensible defaults.

Log state transitions, error codes, negotiated capabilities and aggregate timing only. Never persist passwords, typed text, clipboard contents, screenshots, or raw keyboard streams. Diagnostic export is explicit and redacted. Do not automatically upload telemetry.

## 9. Milestones and completion gates

| Stage | Deliverable | Evidence required |
|---|---|---|
| 0 — Prepared environment | Libraries, scaffold, handoff, link probe | Actual setup report and successful probe |
| 1 — Local keyboard proof | Native app, release first, public-API capture | Physical Command+Tab received; Mac switch suppressed; escape/focus/error tests pass |
| 2 — RDP vertical slice | Connect, render, mapped input, disconnect | Task View actually opens on Windows; Mac escape works without disconnect |
| 3 — Usable native client | Saved PC, required Retina/DPI support, fullscreen, resize, permissions/trust UX | Retina matrix verified on available displays; repeatable capture/release; accurate cursor; no stuck modifiers |
| 4 — Performance | Retina quality/performance comparison and targeted optimization | Equivalent native-resolution Windows App/SDL/custom runs; sharpness, latency and memory recorded; hardware claims verified |
| 5 — Optional capabilities | Gestures, clipboard/audio, more presets | Each feature passes independent lifecycle/permission tests |

Do not begin gesture recognition, multi-monitor, a theme system, or a hardware-decoder fork before the keyboard/RDP slice works. If public APIs cannot capture a required combination on this OS, record the exact result and available alternative. Do not silently redefine Win+Tab as a button-only feature and call the keyboard requirement complete.

Use `KEYBOARD-TEST-PLAN.md` for manual and automated gates and `PERFORMANCE.md` for comparison. Preparation is complete only for the items recorded in `SETUP-STATUS.md`; all application milestones start as untested.

## 10. Build and distribution boundaries

Homebrew development libraries are sufficient for local exploration; a distributable app cannot assume `/opt/homebrew` exists. Later package the chosen dylibs/frameworks and plugins, audit `@rpath` and transitive dependencies, preserve license notices, and test on a clean user account/Mac. Record exact sources, versions, flags, and patches for a release. Do not patch the global Homebrew library to test an optimization; build into a project-local ignored prefix.

FreeRDP is Apache-2.0, SDL is zlib-licensed, and codec dependencies have their own build-dependent terms. Inventory the actual release dependency graph before distribution. Do not copy Microsoft's proprietary client or assets. [FreeRDP project](https://github.com/FreeRDP/FreeRDP), [Homebrew formula](https://formulae.brew.sh/formula/freerdp).

A local app can initially use development signing. Stable signing, Hardened Runtime, notarization, and any App Store sandbox constraints are a later packaging stage; do not claim a Homebrew-linked prototype is distribution-ready. Neither a paid account nor a new signing certificate is needed to inspect/build the current dependency probe.

## Confirmed prototype additions — 2026-10-24

The user confirmed the native capture/release prototype first and requested gesture recognition, saved credentials and an app PIN in this milestone. Four-finger movement should release to Mac; three-finger left/right movement should map to previous/next Windows desktop. Implement public touch handling now, preserve system gestures, and report real delivery separately. This overrides the earlier suggestion to defer gesture investigation; actual Windows actions still require the RDP bridge.

Save Windows passwords in Keychain when Remember is enabled. Require an app PIN on every process launch, keep the workspace unlocked until the user explicitly locks it or quits, and provide a visible Lock button. PIN minimum is **four digits**, with confirmation on setup/change and retry throttling. Use system Keychain and standard system cryptographic primitives. Never ask for the PIN or Windows password in chat.

## Confirmed full client scope — 2026-10-24

The user requested full implementation now: saved PC list with add/edit/delete, real FreeRDP connections, remembered passwords, Retina support and configurable shortcut/three-/four-finger gesture mappings, including Disabled. Mac input and Mac desktop changes must preserve the session until explicitly disconnected/closed. Develop and test in code without controlling the user's screen or interrupting to request manual tests. Use a real protocol fixture for automated delivery checks; record Windows authentication and physical/visual acceptance separately. See [CLIENT.md](CLIENT.md) for implemented behavior and results.
