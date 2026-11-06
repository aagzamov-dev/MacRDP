# Native RDP client

## 0.3.19 test — remove the fullscreen startup deadlock (2026-11-06)

Version 0.3.18 introduced a pre-connection fullscreen wait. Native reproduction
showed that replacing the hosted remote view could cancel its completion callback
and leave the model's transition flag set, preventing transport startup indefinitely.
That wait and its view-owned completion have been removed. The client again connects
using the actual current window geometry, then enters fullscreen after connection,
as in 0.3.17. Window delegate completion clears transition state synchronously before
refreshing the current view, even if an earlier view was replaced or detached.

The accepted-layout cache, authentication-stage forwarding, pre-handle resize queue
and initial native layout snapshot fixes remain. These address lost size updates
without making connection depend on a replaceable view's delayed callback. The old
failure was reproduced with real native view replacement; the corrective regression
checks replacement/reattachment and fullscreen completion. The exact sequence in the
user's reported black session and real Windows visual recovery remain unobserved.

## 0.3.18 test — connection size and fullscreen startup (2026-11-06)

Fullscreen connections now wait for native fullscreen layout to settle before
starting RDP. The initial desktop resolution and Windows scaling use the session
view's final backing geometry. Connection-time size changes remain queued through
sign-in and native transport creation, and the latest queued layout is applied to
the initial RDP settings before connecting. This also covers hosts without dynamic
display-control support. Connected/display-capability events recheck current geometry.

Login sheets finish closing before fullscreen is requested. A failed or ignored
fullscreen request falls back to the current window's settled geometry; entering a
new transition cancels an older layout callback. A fullscreen animation that has
actually started is not timed out. The client no longer relies on a fullscreen jump
after connection to obtain the intended starting resolution.

Automated/native checks cover these timing paths and real localhost RDP fixtures
verify final Retina framebuffer dimensions with and without display-control support.
Repeated connections to the user's Windows host, actual native fullscreen animation
and Windows DPI behavior remain manual acceptance checks. Hosts and individual Windows
applications may still impose their own scaling limitations.

## 0.3.17 test — enabled audio defaults and per-PC controls (2026-11-06)

Speaker playback and microphone sharing default to enabled for new PCs. Existing
PCs are switched on once at first launch of this version, as requested; subsequent
per-PC opt-outs remain saved. macOS microphone permission is still required before
a microphone-enabled connection can start.

**Settings → Session → Session controls → Position** remains the app default.
Each PC can choose **Use app setting** or its own position in **Edit PC → Advanced
settings**, or change the position from its live session controls. Overrides are saved
per PC and take effect immediately. Clearing an override restores the app default;
changing Settings moves only sessions that follow that default. New PCs follow the
app setting automatically.

## 0.3.16 test — Mac speakers and microphone (2026-11-06)

In **Edit PC → Advanced settings**, enable **Play Windows audio on this Mac** to
hear the remote desktop through the Mac's selected output. Enable **Use Mac microphone
in Windows** to redirect the Mac's default input device. Save and reconnect for audio
changes to take effect. Existing profiles retain their playback setting; microphone
sharing defaults off.

On the first microphone-enabled connection, macOS asks for microphone access. No
permission is requested on launch or for PCs without microphone sharing. A denial or
restriction stops that connection with instructions to enable access under
**System Settings → Privacy & Security → Microphone**, or turn microphone sharing off
for that PC. Disconnecting or quitting closes capture. Locking MacRDP, Mac sleep or
session deactivation disconnects microphone-enabled sessions to stop recording; ordinary session
focus changes keep calls connected. Non-microphone sessions retain their existing lock behavior.

The packaged pinned FreeRDP build explicitly uses its native Mac rdpsnd/audin backends.
A small upstream patch supports mono and stereo 16-bit PCM capture and rejects formats
that do not match its buffer allocation. Permission/lifecycle, addin resolution and
format tests use injected responses/synthetic data without opening audio hardware.
Real Windows playback, recording, device routing and call quality remain manual checks;
Windows must permit RDP audio playback/recording redirection.

Manual acceptance: enable playback and play harmless Windows audio; enable microphone
and approve the macOS prompt, then check the Windows input-level meter without saving a
recording. Check a denied-permission attempt and reconnect with microphone sharing off.
Confirm that switching windows preserves the call and locking MacRDP stops the microphone
connection while a second, non-microphone PC remains connected. These physical checks
have not been performed by the agent.

## 0.3.15 test — multiple PCs and Mac-mode input (2026-11-06)

Connect to several saved PCs at once; each opens in its own window. Connecting to
an already active PC brings that window forward. Each connection, login prompt,
retry and disconnect is independent. Lock releases input across all sessions while
keeping established connections; quit ends all sessions.

Mac mode now keeps ordinary typing, pointer input and two-finger scrolling working
in the focused Windows desktop, including Actual pixels view. Mac shortcuts and
desktop gestures stay local. Command+V pastes Mac clipboard text into that PC without
switching to Windows mode; the existing Paste action remains available in both modes.
Per-PC paste permission applies. Clipboard contents are read only when requested.
Only the focused session may import remote clipboard updates.

The separately signed **MACRDP TEST** app uses the original saved PCs/settings as
fallback defaults and shares existing PIN/password records through Keychain. Read
[test data sharing](RELEASING.md) before changing credentials. It needs its own
Accessibility permission and release verification for exclusive Windows shortcuts.
The original app stays installed and running. Automated/native checks and localhost
RDP concurrency pass; physical shortcuts, trackpad behavior, Windows clipboard paste
and real Retina presentation still require manual testing.

## 0.3.0 — rendering and session improvements (2026-10-28)

The session uses asynchronous Metal pipeline setup, a reusable private desktop texture and at most three reusable shared staging buffers. The bridge accumulates dirty regions until a snapshot is consumed. Partial snapshots update only the affected texture region; a fresh session, surface resize or renderer recovery requests a complete image. GPU commands retain their source frames until completion. Failed Metal setup or execution falls back to full CoreGraphics snapshots. The decoder remains the installed FreeRDP software path; Metal presentation is not hardware video decoding.

Frame preparation starts when updates arrive, independently of the main run loop. The display link sleeps between updates and while the session is hidden, on another Space, minimized or locked. The renderer presents at up to 60 Hz when the host supplies updates. The icon-only controls remain; **Display & performance** adds resolution/fit controls and aggregate codec, copy-rate, graphics-command and GPU-completion statistics. GPU completion time includes queue time and is not network or key-to-pixel latency.

Connection failures retain a visible error and Retry/Enter login actions. An established session with a saved password can retry a transient network failure up to five times (2/4/8/16/30 seconds); cancellation, lock and explicit disconnect stop pending retries. Authentication and certificate failures do not retry. Automatic recovery does not activate a background session window. Saved PCs support search, favorites, recent connections, duplication without copied credentials, and remembered window positions.

Each PC can override the keyboard mapping and inbound clipboard setting, choose fixed resolution or dynamic Retina size, select fit or actual-pixel view, enable audio playback, and select Mac text/IME input. In actual-pixel view, switch control to Mac and scroll to pan; Windows mode keeps normal remote scrolling. Windows UI scale stays separate from resolution and local fitting; profile scale changes apply on reconnect. Mac text/IME mode uses native composition and Unicode events, with system-shortcut capture disabled; physical Windows keyboard mode remains the default. Audio uses FreeRDP's bundled native Mac output backend and defaults off; microphone capture stays disabled.

The Windows actions menu provides Ctrl+Alt+Delete, Task Manager, desktop switching and **Paste Mac text into Windows**. Outbound text is read only for that explicit action, announced through the clipboard channel, then pasted after acknowledgement. It is cleared on input release and protected against stale acknowledgements. It does not continuously mirror the Mac clipboard. Per-PC policy can disable the action. Existing Windows-to-Mac text sharing remains available.

Code-only checks are recorded in SETUP-STATUS.md. This version has not been launched or connected to Windows by the agent, as requested. Runtime Metal compilation, real GPU presentation, audio, IME, clipboard interoperability, recovery and Retina visual acceptance require the user's manual test. The optional offline Metal compiler is absent from this Xcode installation; the small shader is compiled asynchronously by Metal at app runtime, with the CoreGraphics fallback retained.

### Manual checks for this build

1. Connect with Retina and Match window, scroll/drag windows and compare sharpness. Open Display & performance to inspect actual delivered FPS and observed codec.
2. Resize/full-screen, change resolution, then try Actual pixels and pan while control is set to Mac. Check pointer alignment at corners and after returning from another Space.
3. Use Ctrl+Alt+Delete and Task Manager; test both clipboard directions, including cancelling or changing focus immediately after Paste.
4. Enable audio or Mac text/IME in PC details and reconnect. Test composition, Cyrillic/Unicode text, modifiers and the normal physical keyboard mode separately.
5. Interrupt/restore the network, cancel an automatic retry, and confirm that reconnect stays visible and a background window does not take focus. Test the keyboard release shortcut while scrolling.

## Historical implementation notes

This replaces the local input prototype. The app now links FreeRDP 3.32.2 and implements real RDP sessions. Implementation and code-only integration tests are complete for the features below. Physical keyboard/trackpad acceptance and an authenticated session on the user's Windows PC remain separate verification work.

## Current input, windows and updates

New sessions prefer Windows control. The session status button reports actual capture, ordinary typing, setup/permission requirements, pause, or a capture failure; selecting Windows alone never establishes that shortcuts are captured.

Open **Keyboard setup & permissions…** from the session panel, menu bar, or Settings:

1. Click **Open Accessibility**, enable this running copy of MacRDP in macOS, and return. The app checks permission every second and offers **Check again**. It never grants itself permission or edits macOS permission databases.
2. Press the displayed escape shortcut in the setup window and click **Release to Mac**. These checks stay local and never forward keys to Windows.
3. Connect to a PC, then click **Start 10-second test**. The app waits for the remote surface to own focus, captures, and displays a countdown. Press the escape shortcut before timeout to save setup. Choose Windows again for continuous capture.

**Restart MacRDP** opens the same app bundle as a new instance before terminating the old one. Active-session restart requires an in-app disconnect confirmation. A failed relaunch leaves the existing app open with an error; restart returns to the normal PIN screen. Restart is optional when permission changes take effect immediately. The permission request uses [Apple’s asynchronous Accessibility prompt](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions); restart uses [NSWorkspace’s new-instance option](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance).

Only the configured shortcut in the setup window can pass local verification. Successful captured release is remembered for that exact shortcut. Permission/tap failures do not silently retry exclusive capture. After a valid grant, ordinary typing can upgrade to capture once all setup and focus requirements hold. Held remote input is released before that upgrade. Permission revocation releases capture and requires an explicit retry.

Temporary focus changes and four-finger Mac navigation release keys/buttons without changing the preferred Windows mode. After a four-finger release, capture waits until the remote surface actually loses eligibility and returns; it cannot immediately re-arm during the outgoing gesture. Returning to an eligible remote surface resumes Windows control after modifiers and the shortcut key lift. Explicit Mac selection persists until the user chooses Windows again. Dialogs, secure input, menu tracking and full-screen transitions block forwarding.

The session has its own window. Entering full screen hides the PC-list window to the menu bar and removes the sidebar/status rows from the remote desktop. Click the keyboard-status button at the top to open or close the compact panel. Hovering never opens it. Keyboard input pauses while the panel is open; closing it restores the selected control mode. The bar includes mode, disconnect, settings, resolution and counted presentation FPS (not the display refresh rate). Closing either window hides it without disconnecting; Quit explicitly ends the app. The menu-bar icon offers saved-PC connect, show session, disconnect/cancel, Windows control toggle, settings, lock, updates and quit.

The renderer uses a view-bound display link, skips presentation on inactive Spaces/occluded windows, prepares frame snapshots off the main thread, and copies only the dirty GDI rectangle into the bridge snapshot after the first frame/resize. Consecutive pointer moves are coalesced without crossing button or keyboard events. The last disconnected transport and renderer image are released. Retina remains on by default; hardware video decoding is unchanged.

Sparkle checks signed GitHub release feeds and verifies signed archives before extraction. The Updates page controls automatic checking and supports manual checks and release notes. Checks wait for disconnect, and a pending relaunch is postponed if a session started meanwhile. See [release instructions](RELEASING.md). No Apple Developer account is required for this signed-update path; the app is not notarized.

## Historical initial client flow


MacRDP starts at its PIN screen every process launch. A PIN contains 4–12 ASCII digits. After unlock, the workspace stays unlocked until **Lock** or quit; changing focus or Mac desktops does not relock it. Locking keeps an established RDP session connected and releases all input. Locking during connection cancels that attempt.

The sidebar lists saved PCs. **Add PC** and **Edit PC** provide name, hostname/IP, port, username, optional domain, password, Remember password, Retina optimization, Windows UI scale, and initial full screen. Save a Windows account password, not a Windows Hello PIN. Existing prototype profiles migrate with their identity intact. Passwords are stored in macOS Keychain, separate from non-secret profile preferences. Renaming a PC retains its password. Changing its address/account clears the old password unless a replacement was entered. Disabling Remember or deleting a PC removes its saved password. A failed replacement write preserves the previous password.

Select a PC and press **Connect**. A missing saved login opens an in-app secure form. Errors provide account/network-specific recovery, **Reconnect**, and **Enter login**. One connection is supported at a time. Browse other saved PCs and return through the active-session button; browsing does not disconnect.

Untrusted RDP certificates require **Trust once** or **Trust this PC** after reviewing host, subject, issuer and SHA-256 fingerprint. Normal certificates use macOS SSL hostname/chain validation. Persistent trust is scoped to the profile's address and port; a changed fingerprint stops for a new explicit decision. **Forget trusted certificate** removes that host pin. Kerio trust and global macOS trust are untouched.

The session has Windows input, Mac input, full screen, and Disconnect controls. The footer shows actual received remote pixels, display-control availability, input state and the saved toggle shortcut. The native toolbar always provides Release, Settings and Lock while unlocked. Returning to Mac input, changing Spaces, showing settings, minimizing, and losing focus release input while preserving the connection. Explicit Disconnect, quit, transport loss, or an input-queue failure ends it. Window close now hides to the menu bar. A normal RDP disconnect does not log out Windows.

## Shortcut and gesture settings

The default toggle is **Control+Option+Command+G**. Click the shortcut in Settings to record a replacement, then Save. It must include Control, Option or Command. Tab combinations and Force Quit cannot be assigned. The completing toggle key is consumed, held remote modifiers are released, and recapture waits for all toggle keys to lift. Changing the binding resets its release verification.

Ordinary keyboard, pointer, buttons and scrolling use AppKit and require no global input permission. Command maps to Windows, Option to Alt, and Control to Control. Capturing macOS-reserved combinations requires the separate **Capture Mac system shortcuts** option and MacRDP's Accessibility authorization. The app first requires shortcut rehearsal and the visible Release button. The first captured attempt times out after ten seconds; successfully releasing it with the captured shortcut enables continuous capture for the current process. A binding change requires verification again; successful captured release is now persisted across restarts. A dedicated watchdog releases input if focus/permission/tap health changes or the interface heartbeat stops. Force Quit remains available. This flow is implemented; physical interception on this final build has not been claimed as passed.

Three fingers default to Windows desktops left/right. Four fingers default to Mac desktops/release input. Either finger count can instead use Windows desktops, Task View, Mac desktops/release, or Disabled. Windows actions commit on lift, allowing a fourth finger to take priority. Four-finger Mac release can occur as movement crosses the threshold. The app never hides or exits full screen because of a gesture. macOS can reserve gestures before delivering touches to apps; changing the mapping does not change global trackpad preferences or guarantee interception. Space-change notifications release capture even if macOS consumes the gesture.

## Session controls and scrolling

In **Settings → Session**, choose top left, top center (default), top right, bottom left, bottom center, or bottom right for the menu and Windows desktop buttons. Bottom positions open the menu above the buttons. Saving applies to the current session and persists across restarts.

Enable **Reverse horizontal scrolling** to flip left/right two-finger or horizontal mouse-wheel scrolling. It defaults to off and leaves vertical scrolling unchanged. Saving a direction change clears accumulated scroll fractions.

Native smoke checks cover all six saved positions, an unknown-position fallback, compact session previews, positive/negative scroll direction, vertical scrolling, discrete wheels, large-delta splitting, and fractional/reset behavior. Physical touchpad feel in a Windows session still needs manual verification.

## Display and engine

Retina is on by default. The session view's actual `convertToBacking` geometry determines requested remote pixels; Windows desktop scale is independently automatic or explicitly 100–500%. Device scale uses protocol-valid 100. Lower-resolution performance mode is opt-in. Initial geometry is supplied before connecting; changes are debounced 150 ms and sent on the negotiated RDP display-control channel with server area limits. When a server does not support resizing, the current desktop remains fitted and the footer reports a fixed/awaiting mode. Reconnect after changing per-PC display policy when needed; the server may defer Windows DPI changes until reconnect.

The CoreGraphics view displays the active decoded GDI frame and maps clicks against that exact image's letterboxed rectangle, with top-origin remote coordinates. Cursor size and hotspot use the same transform. Backing pixels, Windows UI scale, and local fit are separate. Window/backing/full-screen changes request updated geometry. The renderer coalesces presentation only after FreeRDP has applied protocol updates. It reuses a bridge framebuffer and at most three leased presentation buffers. Static frames do not cause repeated copies or redraws.

Each session has one worker for connect, library input, resize and teardown. Event-tap callbacks only enqueue bounded input. Release clears unsent events by generation, prioritizes remote key/button-up cleanup, and cannot wait on a network write. Queue overflow fails closed and disconnects instead of silently dropping key-ups. Cancelling wakes pending certificate decisions. Session generations prevent old worker callbacks updating a replacement connection. A new connection clears the previous host's displayed image; returning to the same live session restores its cached frame/cursor.

The current Homebrew decoder is software based (`WITH_FFMPEG_HWACCEL=OFF`). H.264/AVC444 capabilities are enabled through FreeRDP's common graphics pipeline, but no particular Windows codec or hardware decode result is claimed. Sound, gateways, other redirection and multiple simultaneous sessions remain outside this requested core implementation.

## Observed verification

All checks below use code only and no screen control. Generated UI previews use synthetic data and offscreen native views.

| Check | Observed result |
|---|---|
| Debug / Release app builds and signatures | Passed; both app bundles built and signature verification succeeded |
| C static analysis | Passed with zero findings |
| Installed dependency doctor and CMake link/context probe | Passed, FreeRDP/WinPR 3.32.2 |
| Swift core behavioral tests | 32 passed: capture/release, stale generations, toggle gating, configurable gestures, scan codes, PC storage/migration, Retina geometry, PIN throttling and secret storage |
| Native smoke tests | Passed: native views, release/lock gates, persisted settings, PC add/edit/delete, password retention/clearing, failed writes, startup lock and connected-session lock behavior, using isolated memory secrets |
| Bridge queue tests | Passed: release during a send invalidates the remaining old batch; resume accepts only new input; overflow clears held keys and disables/stops input |
| Actual localhost TLS/RDP peer | Passed: rejection, pending-certificate cancellation, changed-pin rejection, explicit one-session acceptance and matching saved-pin connection without another prompt |
| Actual CredSSP/NLA authentication | Passed: synthetic NTLMv2 account accepted; incorrect synthetic password rejected; no Windows account or user secret used |
| Actual desktop frames | Passed: received 1600 × 1000 synthetic GDI desktop and exact BGR pixel values; no remote screenshot saved |
| Actual keyboard/mouse delivery | Passed: scan codes including extended Windows modifier and pointer button arrive at server, cleanup arrives on release, and input resumes on the same session |
| Actual display-control negotiation | Passed: requested 1800 × 1200 / 200% / device scale 100 over DISP; received resized desktop |
| Address/undefined-behavior sanitizers | Passed for bridge queue and real RDP integration tests |
| Documented Windows VPN host | RDP certificate reached; deliberately rejected. No certificate accepted, credentials supplied or authenticated desktop claimed |
| Physical Command+Tab capture and gestures | Not tested on this final build; earlier capture failures remain recorded in the historical prototype guide |
| Real Windows Retina visual/cursor/DPI acceptance | Not tested; manual matrix remains NOT TESTED |
| Windows App responsiveness or hardware decode parity | Not tested; no performance claim |

The temporary server fixture uses FreeRDP's peer and channel APIs with a disposable self-signed certificate and synthetic credentials. The fixture exercises both a TLS-only peer and a peer requiring CredSSP/NLA with a synthetic NTLMv2 password validator using WinPR APIs. It has no Windows OS account service. The product client retains NLA and TLS, rejects legacy RDP security, and does not bypass certificate checks. Fixture success proves actual RDP authentication/transport/display/input integration, not login to the user's Windows account or Task View's visible behavior.

Relevant matching upstream references: [FreeRDP 3.32.2 sample client](https://github.com/FreeRDP/FreeRDP/blob/3.32.2/client/Sample/tf_freerdp.c), [common client/channel handling](https://github.com/FreeRDP/FreeRDP/blob/3.32.2/client/common/client.c), [sample server](https://github.com/FreeRDP/FreeRDP/blob/3.32.2/server/Sample/sfreerdp.c), [display-control server](https://github.com/FreeRDP/FreeRDP/blob/3.32.2/channels/disp/server/disp_main.c), [Apple backing conversion](https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)-3zors), and [display-control layout rules](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpedisp/ea2de591-9203-42cd-9908-be7a55237d1c).

## Local build boundaries

The native app targets **macOS 27.0+ / arm64**, matching `LC_BUILD_VERSION` of the installed FreeRDP/WinPR dylibs. The standalone Swift core can compile for macOS 14; that is not an application compatibility claim. Development builds link the installed `/opt/homebrew` dependency tree. Debug and Release are development signed. Bundled dependency licensing, a portable app, notarization and testing on another Mac remain distribution work, not silently claimed complete.

Use `scripts/build-app.sh`, optionally `MACRDP_CONFIGURATION=Release`. Outputs remain under `build/app/Build/Products/Debug` and `Release`. The stable Debug path matches the app previously authorized by the user. Rebuilds or another app path may require macOS to reconsider its own permission. No app was launched or permission changed by the agent during this code-only implementation.

## Selectable keys and desktop gestures

Settings now maps physical Command, Control, Option and Shift independently to Windows Ctrl, Windows, Alt, Shift or Disabled. **Command copies & pastes** selects Command→Ctrl, Control→Windows, Option→Alt, Shift→Shift. The release shortcut and macOS Force Quit always use physical Mac keys and remain outside mapping. Left/right modifiers are preserved, and shared targets stay down until all corresponding physical keys are released. Changing mappings releases remote input before replacing the translator; mapping applies equally to event-tap and ordinary AppKit keyboard input.

Three-finger horizontal swipes send the fixed [Windows Ctrl+Windows+Left/Right shortcut](https://support.microsoft.com/en-us/accessibility/windows/keyboard-shortcuts-in-windows), independently of selected modifier mappings. The recognizer now retains a completed movement across partial or empty finger-lift events, keeps four-finger priority, and rejects cancelled gestures. A second Windows virtual desktop must exist. The session’s **Desktops** menu provides Previous/Next buttons to test the same remote action. Settings shows the last gesture result and provides Trackpad settings access when macOS claims the gesture; global gesture preferences are never changed by the app.

Credential access uses a fixed, certificate-verified helper to retain Keychain authorization across app rebuilds. See [release and installation instructions](RELEASING.md). The existing PIN and password records are preserved; the first migration may prompt once per existing Keychain item.

## Windows → Mac text clipboard

Text clipboard sharing is enabled by default. Copy text in Windows using the configured copy shortcut (Command+C with the **Command copies & pastes** preset, otherwise the key mapped to Windows Ctrl+C) or a Windows Copy menu, then switch to a Mac app and paste normally.

Disable **Settings → Session → Clipboard → Share text clipboard: Windows → Mac** and save to stop sharing immediately. The preference persists across restarts; enabling it again applies to subsequent Windows copies without reconnecting. Text already copied to the Mac stays there when sharing is disabled or the session ends.

Only Unicode plain text is imported; Windows line endings become Mac line endings. Images, files, rich formatting and Mac → Windows clipboard sharing are unsupported. Mac clipboard contents are never read or sent to Windows. Sharing does not write to the Mac clipboard while MacRDP is locked or disconnected. Delayed responses from earlier settings or sessions are discarded. Text responses above 16 MiB or malformed UTF-16 are ignored, and clipboard contents are never logged.

Validation for this change uses mock channel callbacks, an injected clipboard writer and text decoding tests. No live Windows copy/paste or application launch was performed.

## Keep awake

Settings → Session → Power includes **Keep awake while connected**, enabled by default. Save settings to apply the choice immediately to the current session and future connections. While enabled and connected, MacRDP prevents idle system and display sleep, including when another app has focus. Disconnect, connection failure and app shutdown release the activity. Manual Sleep and lid-close behavior remain controlled by macOS.

## Separate test installation

`bash scripts/package-test-app.sh 0.3.0` builds **MacRDP Test.app** with bundle identifier `uz.macrdp.test` in a separate generated source directory. The main project identity and fixed production credential helper remain unchanged. The test app uses its own preferences, `uz.macrdp.test.credentials` Keychain service and `uz.macrdp.test.keychain` helper identity; the helper accepts only the test app signed by the same certificate. Normal-release updates are disabled. Set up its PIN, PCs and Accessibility authorization separately. The script builds, signs and packages only; it never launches or installs the app.

### Mac authentication and forgotten PIN (0.3.1 test build)

The lock screen offers native Touch ID or Mac login password authentication, using Apple's `deviceOwnerAuthentication` policy. Choose **Forgot PIN? Reset with Mac account** to authenticate and save a new 4–12 digit PIN without removing saved PCs or passwords. The same reset is available in Security settings. Cancellation or failed authentication does not reset the PIN. A successful reset also recovers a malformed PIN record. MacRDP Test retains its separate `uz.macrdp.test` identity and Keychain service; the main application's PIN is not automatically shared.

Reference: https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication

Validation: 56 core tests passed, including reset preservation, invalid/write-failure rollback and PIN throttle recovery. Headless model checks passed for authentication success, cancellation, reset and late completion after locking. No app launch, native authentication prompt, or live RDP connection was performed; Touch ID/password dialog behavior remains for manual testing.

### Optional Dock hiding (0.3.4 test build)

Settings → Session → Dock includes **Hide Dock while controlling Windows**, off by default. Enable it and save to prevent edge-hover Dock activation during normal Windows input or exclusive capture. Release to Mac, application/window focus loss, local dialogs, disconnect and shutdown use the existing input cleanup to restore the saved presentation options. The setting does not change global Dock preferences or the floating session controls.

Headless checks with injected presentation options passed for persistence, normal/exclusive modes, toggling off, release, focus-loss cleanup and shutdown. Actual Dock behavior requires manual testing; no app was launched.

### Per-PC VPN and full-screen Dock handling (0.3.5 test build)

Edit a saved PC → VPN → enable **Use VPN before connecting**, select the exact saved macOS VPN profile, and optionally enable **Disconnect VPN when session ends**. Windows connection waits for VPN connected status (up to 60 seconds), with cancellation and a clear error if startup fails. Normal automatic RDP retries retain the VPN. A VPN already connected or connecting is never claimed or disconnected by MacRDP. Only successful start requests made by this process are eligible for non-forced cleanup. An unfinished VPN start is cleaned up on failure/cancel even when the keep-connected option is selected. macOS may retain a shared connection needed by another app.

Read-only compatibility check found both installed Kerio profiles using SystemConfiguration service discovery and status queries. This does not prove live authentication/start/stop behavior: no VPN was started or stopped for validation. Kerio configuration, passwords, persistent mode and certificate trust were not read or changed. The integration uses the selected profile's existing saved login and normal macOS VPN handling.

Dock hiding now also participates in the full-screen presentation callback and is reapplied after entering/exiting full screen. This update enables the setting once, including upgrades from the prior default-off build; subsequent user choices remain saved. The existing release/focus-loss cleanup and floating controls remain in place.

Validation: 57 core tests; headless tests for VPN readiness, reused/pre-existing connections, ownership, keep-connected behavior, failures/timeouts/cancellation and late completion, plus VPN failure preventing RDP creation. Dock option and full-screen presentation restoration checked with injected settings. App and real VPN connections were not run. Manual checks still required: selected Kerio login, Windows readiness, app-owned VPN disconnect, existing-VPN preservation, and Dock edge hover/release in full screen.

### Kerio corrections (0.3.6)

The first VPN integration incorrectly treated every macOS Kerio service record as a current saved Kerio profile. Read-only inspection found two OS records but only one saved Kerio profile label. Discovery now matches Kerio service names against the profile descriptions in its user configuration, retaining only descriptions and never copying credentials or configuration into diagnostics. No records are deleted or modified. The checked machine now exposes only `baik_vpn`; reselect it if a saved PC still references the unavailable `baik.uz` record.

Removed the premature two-second failure while a newly requested VPN still reports disconnected. Initial readiness now waits up to the full 60-second limit; an observed connecting-to-disconnected transition still fails. Provider status codes are shown when available, without assuming a password or certificate cause. Both old records last reported code 7, whose meaning was not established. Regression checks cover delayed startup and profile-label extraction. Read-only discovery verified one entry. This is not live confirmation of automatic Kerio startup: no VPN or app was launched.

### Kerio menu integration (0.3.7)

The user confirmed that Kerio's own menu connects successfully while generic SystemConfiguration starts fail. Kerio profiles now use public Accessibility actions on the running Kerio status app: open its status menu and press the exact saved profile name. Generic macOS VPNs retain their original API path. MacRDP never extracts Kerio passwords or sends private provider options. Keep Kerio running with its status icon visible and grant Accessibility to this MacRDP copy. The current menu adapter recognizes Kerio's English `Disconnect` action; unsupported or ambiguous menu layouts fail with a visible error instead of guessing.

Connection status is still checked before starting Windows. Pre-existing VPNs are not touched. Cleanup only applies after this process successfully pressed the profile action; it verifies the selected service remains active, rejects other active profiles, and stops claiming a connection whose observed session timestamp changes. Cancellation drains an in-flight menu start before cleanup. Normal app quit waits for VPN cleanup before exiting. Cleanup may fail if Kerio disappears, permission is revoked, or its menu changes; the app then asks for manual disconnect. Forced process termination cannot guarantee menu cleanup.

Validation: headless tests passed for exact-profile menu selection, ambiguity rejection, other-profile preservation, delayed readiness, ownership, cancellation during start and exactly-once cleanup. Native smoke target compiled only. The computer-use inspection timed out; no Kerio menu action or live VPN start/stop was executed, and the test app was not launched. This new path still requires manual verification with Kerio 9.6.1.


### Current VPN behavior: passive waiting only (0.3.8)

Supersedes the automatic VPN behavior described in 0.3.5–0.3.7. All VPN start/stop calls and the Kerio menu adapter were removed. In PC details, enable **Wait for VPN before connecting** and select the saved VPN. The app shows **Waiting for VPN connection** until that VPN reports connected, then proceeds to Windows. Connect/disconnect the VPN yourself. Waiting has no timeout and can be cancelled; cancelling, disconnecting Windows, locking, or quitting never changes the VPN. Existing saved selections continue to work; obsolete automatic-disconnect fields are ignored.

Dock hiding is now based on the foreground Windows session and Windows input selection, independently of keyboard capture or floating-control focus. It remains enabled by default, restores on explicit Release to Mac/app switch/local dialogs, and rechecks presentation options while active. The floating controls are unchanged. Validation: 57 core tests and injected headless tests passed for passive waiting, cancellation, Dock eligibility, restoration and reapplication. App and live Dock behavior were not run; manual confirmation remains required.

### Active-window Dock rule (0.3.9)

Dock hiding now depends only on the enabled setting and the remote-session window being the active app's main visible window. Mac input, Windows input, disconnected/waiting screens, and floating controls all use the same rule. Leaving the session window restores the previous presentation options. Focus lifecycle callbacks apply the rule immediately, with the existing timer as a fallback. VPN remains manual-only. Headless checks/build only; the app was not launched. The built app is delivered on the Desktop.


### Full-screen Dock recovery after app switching (0.3.10)

The previous recovery could write an unchanged requested presentation value when the effective system state had reverted to auto-hide. Recovery now transitions through a valid auto-hide value before reinstating hideDock when requested and effective state disagree. Stable state produces no extra writes. Full-screen delegate options no longer replace the saved application restoration state; application updates retain AppKit-owned full-screen/toolbar flags. VPN remains passive/manual-only; floating controls are unchanged.

Validation: headless injected-state tests cover repeated switch/return divergence, a setter ignoring unchanged requests, stable-state writes and restoration. This models the reported failure path; it is not a live reproduction. App switching and bottom-edge hovering in real fullscreen remain user acceptance checks. Test app built without launching.


### Dock hiding removed (0.3.11)

Removed the optional Dock hiding setting, preference migration, focus callbacks, full-screen presentation override, effective-state recovery and timer-based presentation checks after user testing found the behavior unreliable. Old saved Dock preferences are ignored. Normal session input leaves presentation options alone. Exclusive keyboard capture retains its original auto-hide/process-switching behavior, with restoration on release, focus loss and shutdown; Force Quit remains available. Manual VPN waiting and floating controls are unchanged. No rendering or transport changes were made.

Validation uses headless capture cleanup and passive VPN tests, core tests and a signed Release build. No app was launched; smoothness improvement has not been measured.
