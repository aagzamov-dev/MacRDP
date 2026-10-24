# Keyboard capture acceptance plan

All application results start **NOT TESTED**. The dependency probe proves linking/initialization only.

## Test order

1. Build a stable native app bundle. Run local mode with a visible mouse-operated Release control. Verify no keyboard interception outside the app.
2. Implement the release chord and cleanup before capture. Use an early-prototype automatic release timer. Verify macOS Force Quit remains available.
3. Enable capture locally. Test real physical keys, both full screen and windowed. If macOS consumes a shortcut, record it; do not infer success from a tap flag or synthetic event.
4. Connect to the intended Windows test machine, with user-entered credentials, and repeat. Use a harmless Windows test window. Observe the actual remote result.
5. Repeat failure/lifecycle tests and a modest stress run before removing the automatic timeout.

## Manual matrix

Record OS/build, keyboard/layout, app build/signing identity, permission state, display configuration, connection address, and date. Do not record credentials or typed private text.

| ID | Action | Required observation | Result |
|---|---|---|---|
| K01 | Command+Tab in captured session | Windows Task View; no Mac app switch | NOT TESTED |
| K02 | Option+Tab, including held Alt and repeated Tab | Windows app switch; release ends switcher | NOT TESTED |
| K03 | Control+Tab / Control+Shift+Tab | Remote tabs move once in correct direction | NOT TESTED |
| K04 | Configured toggle (default Control+Option+Command+G), in both directions | Local ownership promptly; no remote completing key; next toggle captures only after keys lift; session/window unchanged | NOT TESTED |
| K05 | Command+Tab after release | Normal Mac app switch | NOT TESTED |
| K06 | Toggle from full screen; four-finger macOS Space swipe | Toggle preserves full screen/window; swipe allows normal macOS desktop navigation with session open and connected; returning restores Windows control after keys lift, while explicit Mac mode remains local | NOT TESTED |
| K07 | Click Release and open local settings | Local controls receive keys; remote receives none | NOT TESTED |
| K08 | Hold Control/Option/Command, then release/focus-change | No stuck remote modifiers; no unexpected local shortcut | NOT TESTED |
| K09 | Command+R/E/D and Control+C/V | Correct Windows actions under physical mapping | NOT TESTED |
| K10 | Control+Command+Left/Right | Windows virtual desktop change when available | NOT TESTED |
| K11 | Left/right Shift/Control/Option/Command, Caps Lock | Correct press/release; layout and AltGr behavior documented | NOT TESTED |
| K12 | Hold/repeat ordinary key; rapid chords | No duplicate delivery or lost release | NOT TESTED |
| K13 | Hide, minimize, switch app, close window | Automatic release and remote key/button cleanup | NOT TESTED |
| K14 | Certificate/authentication dialog | Capture releases before native input; passwords never forwarded | NOT TESTED |
| K15 | Deny/revoke required input permission | Clear state; normal local input; capture does not claim success | NOT TESTED |
| K16 | Disconnect/network loss while modifier held | Local release immediate; no wait for unreachable peer | NOT TESTED |
| K17 | Disable tap / induce callback timeout in test build | Capture leaves safely; recovery requires explicit action | NOT TESTED |
| K18 | Sleep/wake, lock/unlock | No stale capture or modifiers after return | NOT TESTED |
| K19 | App crashes / Force Quit during capture | Normal macOS input returns; no persistent global configuration changes | NOT TESTED |
| K20 | Repeat capture/release 50 times; reconnect 10 times | No growing handler count, retained session, or stuck key | NOT TESTED |
| K21 | Built-in and external keyboard; English/Russian layouts if used | Scan-code behavior and text mode both documented | NOT TESTED |
| K22 | Three-/four-finger gestures | Exact supported behavior recorded; shortcut escape always works | NOT TESTED |
| K23 | Escape and pointer input during Retina resize/decoding load | Prompt local release, accurate cursor, no stale modifiers after display changes; see [Retina matrix](RETINA-DISPLAY.md) | NOT TESTED |

K22 is optional and does not gate the initial keyboard milestone. Other unavailable hardware/layout combinations may be recorded as not tested with a reason. Never mark an entire row passed based solely on a unit test.

## Automated behavioral tests to implement with the input controller

- A captured stream sends one ordered press/release per physical action, including repeat semantics and separate left/right modifiers.
- Escape is detected before forwarding its completing key. Previously sent modifiers are released once. Repeated escape/cleanup is harmless.
- No new remote events after releasing, losing focus, opening a local field/dialog, or disconnecting. Events already queued for an old session cannot reach a replacement session.
- Ordinary input forwarding is blocked during arming until permission/session/focus requirements hold. Re-entry waits for escape modifiers to be lifted.
- Modifier and mouse-button cleanup occurs on every transition, even when a transport error makes sending key-ups impossible.
- Queue overflow or a stale session disables capture rather than dropping a key-up silently or blocking the tap.
- Tap-disabled callbacks and simultaneous disconnect/resize/focus-loss cannot access released FreeRDP pointers.

Use a mock input sink to inspect event order without requiring a server. Separately run native integration and human physical-key tests. Synthetic events do not prove that macOS will route real system shortcuts identically.

## Observation limits

Never test exit reliability by disabling Force Quit or trapping the user without a timeout/visible release. A whole-process hang may require Force Quit; document that boundary. Do not log a full key stream to disk. A temporary in-app diagnostic indicator may show named test chords only while explicitly enabled, and must be off during credentials or ordinary user typing.

## Keyboard setup regression checks (2026-10-24)

Native smoke coverage now includes denied/granted/revoked Accessibility state, no permission request during read-only checks, failed Settings opening, setup gating, local shortcut verification scoped to the setup window, pending capture across full-screen transitions, actual-tap gating of the active label, and relaunch success/failure using injected closures. Offscreen AppKit fixtures have no live window number, so tests supply the observed window identity directly to the local shortcut handler; physical key routing remains unverified. UI previews cover permission-denied and granted setup in light/dark mode. No real permission was changed or app restarted by these tests.

Manual follow-up: enable this app's Accessibility entry, return without restarting and check detection; revoke it during capture and confirm local input; exercise the optional restart button with both disconnected and connected sessions; confirm Command+Tab opens Windows Task View after a successful timed capture test. These remain NOT TESTED on a live Windows session.
