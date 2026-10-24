# MacRDP

Native SwiftUI/AppKit RDP client using FreeRDP 3.32.2. Includes a saved-PC list, add/edit/delete, Keychain passwords, a 4–12 digit app PIN, Retina display negotiation, dynamic resize, keyboard/mouse input, full screen, configurable input toggle, and configurable three-/four-finger gesture mappings.

Switching to Mac input, changing macOS desktops, or locking MacRDP keeps an established RDP connection open. Disconnect or quit explicitly to close it.

## Build and use

```sh
./scripts/build-app.sh
open build/app/Build/Products/Debug/MacRDP.app
```

The local build requires this Mac's Apple Silicon Homebrew libraries and macOS **27.0+**, matching their actual deployment target. It is development signed and is not a portable/notarized distribution. The separate Swift core package targets macOS 14, but that does not establish older-OS support for the app.

1. Unlock with your existing app PIN, or create one on first launch.
2. Choose **Add PC**. Enter the Windows address and account password inside the app. Enable **Remember password in Keychain** to reuse it.
3. Select the PC and choose **Connect**. Verify any untrusted certificate before explicitly trusting that PC.
4. **Settings** contains the shortcut recorder, system-shortcut capture option, gesture mappings, and PIN change. PC display preferences are in **Edit PC**.

The default input toggle is **⌃⌥⌘G**. Ordinary RDP input works without Accessibility permission. Optional system-shortcut capture requires permission for MacRDP and verified release controls. Its first captured release has a ten-second safety limit; a successful captured shortcut release enables continuous capture for that process. Focus and heartbeat safeguards remain active.

Read [the client guide and verification results](docs/CLIENT.md). Physical system-shortcut interception, macOS-reserved gestures, visual Retina acceptance on the real Windows PC, and Windows App performance parity remain unverified. Code-only testing reached the documented Windows host's RDP certificate; no Windows password was supplied and no authenticated Windows desktop is claimed.

## Code-only verification

```sh
./scripts/doctor.sh
./scripts/build-probe.sh
./scripts/test.sh
./scripts/test-input-queue.sh
./scripts/test-native.sh
./scripts/test-rdp.sh
```

The RDP tests use a temporary localhost FreeRDP peer and disposable test certificate. They establish real TLS/RDP connections, inspect synthetic desktop pixels, change resolution over the display-control channel, deliver keys/mouse events, release held inputs, and resume on the same connection. They also exercise CredSSP/NLA success and wrong-password rejection, certificate rejection, cancellation and certificate pinning. No screen automation or real user credentials are used. A restricted execution environment may require permission to bind a localhost socket.

Build the optimized variant with `MACRDP_CONFIGURATION=Release ./scripts/build-app.sh`. In environments that cannot start the compiler's nested plugin sandbox, append `'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox'`; this concerns compiler plugins, not macOS app permissions.

## Project

- [Product requirements](docs/REQUIREMENTS.md), [current setup status](docs/SETUP-STATUS.md), [development handoff](START-HERE.md).
- [Keyboard acceptance](docs/KEYBOARD-TEST-PLAN.md), [Retina acceptance](docs/RETINA-DISPLAY.md), [performance procedure](docs/PERFORMANCE.md).
- `Sources/MacRDP`: native interface, session ownership, display and event tap.
- `Sources/RDPBridge`: thin C bridge; FreeRDP owns the RDP protocol.
- `Sources/CaptureCore`: PC profiles, geometry, input state, gestures and PIN/Keychain logic.
- `MacRDP.xcodeproj`: application target. CMake builds only the separate dependency probe.

No remote repository or publication has been created. Homebrew versions are recorded in `docs/research/dependencies.json`; `Brewfile` is not an immutable dependency lock.
