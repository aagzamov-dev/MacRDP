Connect to multiple PCs at once in separate windows. Each connection keeps its own input, login, retry and disconnect state, and opening an already connected PC brings its window forward.

- Mac mode keeps ordinary Windows typing, clicking, dragging and scrolling available while Mac system shortcuts stay local. Command+V pastes Mac clipboard text into the focused Windows session.
- Windows sound can play through the Mac, and Windows apps can use the Mac microphone. Both options default on; existing PCs are enabled once after upgrading, and later per-PC opt-outs remain saved. macOS requests microphone permission when connecting to an enabled PC.
- Locking MacRDP, or Mac sleep/session deactivation, disconnects microphone-enabled sessions to stop recording. Other established sessions stay connected.
- Each PC can override the floating controls position, from its editor or live controls. “Use app setting” follows the default in Settings.
- Fixed lost Retina size updates during sign-in and transport startup. Removed the pre-connect fullscreen wait that could leave the test build blank; the corrected connection sequence was confirmed working by the tester.

Validated with 60 core tests, native lifecycle/input/permission regressions, synthetic audio format checks and localhost RDP integration, including concurrent connections and initial Retina sizing without dynamic resize support. Live speaker/microphone interoperability and call quality remain dependent on Windows policy, devices and the network and have not been comprehensively tested.

Install the DMG or use Settings → Updates in the original MacRDP app after disconnecting active sessions. Saved PCs, PIN and Keychain passwords are preserved. This release retains the production app identity, unchanged credential helper and existing update-signing key. It is locally signed, not Apple-notarized. The separate MACRDP TEST app has automatic updates disabled.
