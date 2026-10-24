# MacRDP development instructions

- Inspect this repository and installed dependency versions before changing code. `docs/REQUIREMENTS.md` defines the product; `docs/SETUP-STATUS.md` distinguishes completed setup from future work.
- For keyboard capture, the FreeRDP bridge, or session rendering, read `.agents/skills/macrdp-development/SKILL.md` and the relevant linked document.
- Prefer native SwiftUI/AppKit, FreeRDP 3, and a thin C-compatible bridge. Introduce abstractions only when actual implementation needs them. CMake currently builds only the dependency probe; do not mistake it for an application target.
- Retina is required for the first usable release. Read `docs/RETINA-DISPLAY.md` before implementing session geometry/rendering. Keep backing pixels, remote pixels, Windows scale and local zoom separate; validate quality and input at the user’s actual Retina resolution.
- Prove release and focus-loss cleanup before enabling exclusive capture. Keep normal local input while a password field, native dialog, or another app has focus. Preserve Force Quit.
- Use public macOS APIs. Do not build the product around SDL's private CGS hotkey path. Do not change global keyboard/trackpad preferences or TCC databases, run the app as root, or disable SIP.
- Keep protocol I/O, decoding, and blocking work off the main thread. Serialize library input/lifecycle calls consistently with the pinned FreeRDP API. Never hold an input-event callback while waiting on a network write or UI operation.
- Do not copy credentials, saved keychains, raw key streams, remote screenshots, or VPN secrets into the repository or diagnostic reports. Ask for credentials in the application, not chat.
- Preserve the working Kerio configuration and trust exception. It is unrelated to RDP trust. Use normal RDP certificate verification; an explicit per-host fingerprint decision is separate from global trust.
- Use meaningful behavioral tests for key-up cleanup, escape handling, capture state, and lifecycle races. Build relevant native targets and run those tests after changes. Update recorded manual results honestly.
- No speculative service layers, custom crypto, custom RDP protocol implementation, or unnecessary web runtime. No obvious comments. Strongly type Swift and bridge interfaces.
- Never revert user work, change Windows policy, or perform destructive Git operations without permission. Do not create a remote repository or publish this private project unless requested.
