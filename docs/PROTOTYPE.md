# Historical native input prototype

**Superseded by [the native RDP client](CLIENT.md).** The text below records the earlier local-only milestone and its observed failures. It is historical, not the current app specification; its old deployment/linking descriptions no longer apply.

Implemented 2026-10-24. This is a local keyboard/trackpad feasibility app, not an RDP client yet. It makes no Windows connection. A detected chord or gesture is displayed as **detected locally**; this does not prove delivery to Windows.

## Build and open

```sh
./scripts/build-app.sh
open build/app/Build/Products/Debug/MacRDP.app
```

Or open `MacRDP.xcodeproj` in Xcode and run the shared MacRDP scheme. The native app has bundle identifier `uz.macrdp.app` and a consistent development location. It uses development ad-hoc signing, not a distribution identity. Rebuilds can require macOS to reconsider a Keychain/input authorization; approve only MacRDP itself. Keep its path consistent. No paid signing account is required for this prototype.

The target currently deploys to macOS 14 or newer; only the installed macOS 27.0.1 / Apple Silicon machine has been used for build and view checks. Compatibility on older releases is not established. The prototype does not yet link Homebrew libraries into the app; the dependency probe remains a separate CMake target.

In a restricted build environment that cannot launch Apple's nested compiler-plugin sandbox, the build used:

```sh
./scripts/build-app.sh 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'
```

That flag affects the compiler's plugin process, not macOS permissions or the application's capture behavior.

## First use

1. Create your own **4–12 digit app PIN** in the secure fields. The app starts locked on every process launch. After unlocking it stays open until you press **Lock** or quit; focus loss releases capture without locking the app.
2. Select **Rehearse shortcut** and physically press **Control+Option+Command+G** within ten seconds. Capture remains off throughout rehearsal.
3. Click **Release** in the native toolbar. Both checks must pass in this launch before capture becomes available.
4. Click **Capture for 10 seconds** with all modifiers lifted. If macOS requests Accessibility authorization, grant it to MacRDP through System Settings yourself, return, and explicitly try Capture again. The prototype does not automatically recapture after authorization or focus changes.
5. Test Command+Tab, Option+Tab, Control+Tab and Control+Shift+Tab. Only named supported test chords appear on screen; no raw key stream or typed text is logged.
6. Use **⌃⌥⌘G** to toggle between Mac and Windows keyboard ownership while staying in the same window/full screen. The next capture begins only after the shortcut keys lift. **Release** always returns to local input. A delivered four-finger swipe, Space/focus change, ten-second timeout or failure also releases input. None of these actions hides, minimizes, closes or disconnects the session, or forces it out of full screen.

Force Quit (**Command+Option+Escape**) is passed through and releases capture. Do not disable this system escape. A completely hung process can delay presentation-options restoration; use Force Quit as the independent fallback.

## Gestures

Keep the pointer over the test surface. A delivered four-finger swipe in any direction releases keyboard ownership while leaving normal macOS desktop/Space navigation intact. The app does not force a Space switch, hide or exit full screen; the session remains open until explicitly closed. Three-finger horizontal swipes recognize previous/next Windows desktop actions (Control+Windows+Left/Right); this prototype shows those mappings locally. Actual Windows desktop switching requires the next milestone's RDP bridge.

Three-finger commands commit on first finger lift so a fourth finger can take precedence. Each sequence triggers at most once; cancellation, vertical three-finger movement, and resting touches do not produce desktop changes. Four-finger release cannot be disabled by the three-finger preference.

**Gesture delivery is not guaranteed.** Apple documents that system-wide gestures, including four-finger swipes, take precedence over application handling. If macOS switches away, focus loss releases capture; if it consumes a gesture without moving focus, a release cannot be guaranteed from that gesture. No global gesture settings or private multitouch APIs are used. The keyboard shortcut and visible control remain required.

## Change the keyboard toggle

Open **Settings → Keyboard toggle**. Click the current shortcut, press a new combination and click **Save**. **Escape** cancels recording; Cancel dismisses the form without changing the binding. The default remains **⌃⌥⌘G**. Bare typing keys, modifier-only bindings, Force Quit and the required Windows Tab combinations are rejected. The new binding is saved locally and must pass rehearsal before capture. Recording is restricted to its own focused control; password fields and other windows are excluded.

The shortcut works only while the unlocked session surface owns focus. Both toggle directions keep the session/window intact. Pending recapture is canceled on focus/Space changes, local dialogs or timeout, and never silently resumes after focus returns. Four-finger Space navigation is separate from the toggle.

## PIN and saved PC

**Settings** edits one PC's host, port, account and Windows password. Non-secret profile settings use UserDefaults. **Remember password in Keychain** saves the password to a separate, device-local generic-password item; leaving the password field blank keeps an existing password for the same endpoint/account. Turning Remember off and saving deletes that profile's saved password. Changing endpoint/account invalidates the old credential association. No existing Windows App or VPN credentials are read.

The app PIN is separate from Windows credentials and Windows Hello. Its randomly salted PBKDF2-HMAC-SHA256 verifier uses Apple's CommonCrypto with 600,000 iterations and is held in Keychain. Failed attempts have an increasing delay after five failures, persisted in the lock record across relaunches. **Change app PIN** requires the existing PIN. There is no automatic forgotten-PIN bypass or password export. The PIN is an application access gate; it does not replace your Mac account/Keychain security.

Keychain failures keep the UI locked or show an explicit save error; there is no plaintext fallback. Secure fields never participate in keyboard capture. PIN/password work runs on a separate actor; the event callback performs no Keychain or network work.

## Implementation boundaries

- Explicit local → arming → captured → releasing state with a capture generation, held-key tracking and idempotent cleanup.
- A public session event tap on a dedicated run loop. A separate watchdog expires the capture and detects a stalled main-thread heartbeat. No root/HID tap or private CGS API.
- Valid AppKit presentation options suppress process switching only while captured and restore their previous values afterward. Force Quit and session termination are never disabled.
- Release on app/window focus loss, local controls/sheets, hide/minimize/close, fullscreen transitions, sleep/session inactivity, Accessibility loss and tap failure. No silent recapture.
- Physical left/right modifier flags are decoded separately. The core exercises ordered key transitions; no FreeRDP input sink exists yet. Caps Lock, layouts/IME, RDP mouse input, decoding and remote lifecycle remain for the bridge milestone.
- Native SwiftUI/AppKit screens and native toolbar; no web runtime or third-party UI framework.

## Verification recorded

| Check | Observed result |
|---|---|
| Environment and FreeRDP dependency probe | PASS; FreeRDP 3.32.2, SDL 3.4.18 |
| Xcode native app build and ad-hoc signature verification | PASS |
| Core behavioral tests | PASS; 24 XCTest cases including four-digit PIN, escape cleanup, stale generations, duplicate events, Force Quit pass-through, gestures, PIN change/throttling and credential access gates |
| Native smoke test | PASS; renders lock/workspace screens and checks release/lock/settings gates, named chord mapping, left/right modifier decoding, shortcut persistence/rehearsal reset and retained session-window ownership without creating an event tap or writing Keychain |
| Actual app first launch / locked toolbar | PASS; observed native first-run secure fields and disabled toolbar controls, then user PIN setup succeeded and workspace/toolbar became available |
| Actual release rehearsal timeout | PASS; observed rehearsal returning to local input after ten seconds |
| Shortcut rehearsal and clickable Release gate | PASS; user reported a green shortcut check. Separately, UI automation clicked Release and rehearsed the chord with synthetic input; observed both checks verified and Capture enabled. Synthetic input does not prove exclusive system-shortcut capture |
| Authorized capture startup | Initial attempt FAILED SAFELY at startup; a later automated attempt observed an immediate disabled-tap release. Current build sets eligibility atomically, waits for the input run loop to be ready, keeps AppKit queries out of the callback and performs tap-control calls outside the state lock. Updated physical runtime retest pending; no successful capture claim |
| Physical escape, Command+Tab capture, Force Quit and focus-failure matrix | NOT TESTED; needs physical user input and MacRDP permission authorization |
| Physical three-/four-finger gesture delivery | NOT TESTED; subject to macOS system gestures |
| Real Keychain PIN/password round trip through app | PIN setup, startup-locked relaunch and user-entered PIN unlock PASS. Windows password save/read remains NOT TESTED |
| Rebuilt-app permission gate | PASS; current ad-hoc rebuild stayed local when macOS did not recognize its previous Accessibility approval. User reauthorization requested |
| Actual Windows shortcut/gesture result | NOT TESTED; RDP bridge not implemented |
| Retina remote view/performance comparison | NOT TESTED; no remote renderer |

Run core tests with `./scripts/test.sh` and the harmless native view checks with `./scripts/test-native.sh`. Generated previews/reports stay under ignored `build/`. The native smoke check supplies synthetic UI state in a separate test executable, never a runtime unlock switch in the product.

## Research

- [Apple: application presentation options and valid combinations](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct).
- [Apple: public CoreGraphics event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
- [Apple: normal Accessibility authorization](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).
- [Apple: touch events, identities and system gesture precedence](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html).
- [Apple: Keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility).
- [Apple CommonCrypto: PBKDF2 implementation](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/Source/API/CommonKeyDerivation.c).

Public SDK headers were checked for event modifier masks and secure-event-input detection. No FreeRDP bridge APIs were guessed or added in this milestone.
