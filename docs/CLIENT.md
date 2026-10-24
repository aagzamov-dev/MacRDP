# Native RDP client — 2026-10-24

This replaces the local input prototype. The app now links FreeRDP 3.32.2 and implements real RDP sessions. Implementation and code-only integration tests are complete for the features below. Physical keyboard/trackpad acceptance and an authenticated session on the user's Windows PC remain separate verification work.

## User flow

MacRDP starts at its PIN screen every process launch. A PIN contains 4–12 ASCII digits. After unlock, the workspace stays unlocked until **Lock** or quit; changing focus or Mac desktops does not relock it. Locking keeps an established RDP session connected and releases all input. Locking during connection cancels that attempt.

The sidebar lists saved PCs. **Add PC** and **Edit PC** provide name, hostname/IP, port, username, optional domain, password, Remember password, Retina optimization, Windows UI scale, and initial full screen. Save a Windows account password, not a Windows Hello PIN. Existing prototype profiles migrate with their identity intact. Passwords are stored in macOS Keychain, separate from non-secret profile preferences. Renaming a PC retains its password. Changing its address/account clears the old password unless a replacement was entered. Disabling Remember or deleting a PC removes its saved password. A failed replacement write preserves the previous password.

Select a PC and press **Connect**. A missing saved login opens an in-app secure form. Errors provide account/network-specific recovery, **Reconnect**, and **Enter login**. One connection is supported at a time. Browse other saved PCs and return through the active-session button; browsing does not disconnect.

Untrusted RDP certificates require **Trust once** or **Trust this PC** after reviewing host, subject, issuer and SHA-256 fingerprint. Normal certificates use macOS SSL hostname/chain validation. Persistent trust is scoped to the profile's address and port; a changed fingerprint stops for a new explicit decision. **Forget trusted certificate** removes that host pin. Kerio trust and global macOS trust are untouched.

The session has Windows input, Mac input, full screen, and Disconnect controls. The footer shows actual received remote pixels, display-control availability, input state and the saved toggle shortcut. The native toolbar always provides Release, Settings and Lock while unlocked. Returning to Mac input, changing Spaces, showing settings, minimizing, and losing focus release input while preserving the connection. Explicit Disconnect, quit, closing the app's last window, transport loss, or an input-queue failure ends it. A normal RDP disconnect does not log out Windows.

## Shortcut and gesture settings

The default toggle is **Control+Option+Command+G**. Click the shortcut in Settings to record a replacement, then Save. It must include Control, Option or Command. Tab combinations and Force Quit cannot be assigned. The completing toggle key is consumed, held remote modifiers are released, and recapture waits for all toggle keys to lift. Changing the binding resets its release verification.

Ordinary keyboard, pointer, buttons and scrolling use AppKit and require no global input permission. Command maps to Windows, Option to Alt, and Control to Control. Capturing macOS-reserved combinations requires the separate **Capture Mac system shortcuts** option and MacRDP's Accessibility authorization. The app first requires shortcut rehearsal and the visible Release button. The first captured attempt times out after ten seconds; successfully releasing it with the captured shortcut enables continuous capture for the current process. Restart or a binding change requires verification again. A dedicated watchdog releases input if focus/permission/tap health changes or the interface heartbeat stops. Force Quit remains available. This flow is implemented; physical interception on this final build has not been claimed as passed.

Three fingers default to Windows desktops left/right. Four fingers default to Mac desktops/release input. Either finger count can instead use Windows desktops, Task View, Mac desktops/release, or Disabled. Windows actions commit on lift, allowing a fourth finger to take priority. Four-finger Mac release can occur as movement crosses the threshold. The app never hides or exits full screen because of a gesture. macOS can reserve gestures before delivering touches to apps; changing the mapping does not change global trackpad preferences or guarantee interception. Space-change notifications release capture even if macOS consumes the gesture.

## Display and engine

Retina is on by default. The session view's actual `convertToBacking` geometry determines requested remote pixels; Windows desktop scale is independently automatic or explicitly 100–500%. Device scale uses protocol-valid 100. Lower-resolution performance mode is opt-in. Initial geometry is supplied before connecting; changes are debounced 150 ms and sent on the negotiated RDP display-control channel with server area limits. When a server does not support resizing, the current desktop remains fitted and the footer reports a fixed/awaiting mode. Reconnect after changing per-PC display policy when needed; the server may defer Windows DPI changes until reconnect.

The CoreGraphics view displays the active decoded GDI frame and maps clicks against that exact image's letterboxed rectangle, with top-origin remote coordinates. Cursor size and hotspot use the same transform. Backing pixels, Windows UI scale, and local fit are separate. Window/backing/full-screen changes request updated geometry. The renderer coalesces presentation only after FreeRDP has applied protocol updates. It reuses a bridge framebuffer and at most three leased presentation buffers. Static frames do not cause repeated copies or redraws.

Each session has one worker for connect, library input, resize and teardown. Event-tap callbacks only enqueue bounded input. Release clears unsent events by generation, prioritizes remote key/button-up cleanup, and cannot wait on a network write. Queue overflow fails closed and disconnects instead of silently dropping key-ups. Cancelling wakes pending certificate decisions. Session generations prevent old worker callbacks updating a replacement connection. A new connection clears the previous host's displayed image; returning to the same live session restores its cached frame/cursor.

The current Homebrew decoder is software based (`WITH_FFMPEG_HWACCEL=OFF`). H.264/AVC444 capabilities are enabled through FreeRDP's common graphics pipeline, but no particular Windows codec or hardware decode result is claimed. Clipboard, sound, gateways, redirection and multiple simultaneous sessions remain outside this requested core implementation.

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
