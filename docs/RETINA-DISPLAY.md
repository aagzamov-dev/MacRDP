# Retina display requirements

Added 2026-10-24 at the user's request. **Retina support is required for the first usable release.** The keyboard feasibility prototype can remain minimal, but display geometry must be correct from the first RDP surface. The native renderer and code-only RDP frame/resize integration are now implemented; see [current results](CLIENT.md). The real Windows visual acceptance matrix below remains untested.

## Expected experience

Default to **Optimize for Retina** on a Retina display: sharp Windows text and icons at a comfortable size, accurate pointer placement, smooth scrolling, and automatic adjustment when the session window changes size or display. Standard native Mac controls should remain sharp independently of remote rendering. Compare with Windows App's Retina option enabled, which Microsoft documents separately from image fitting and dynamic resolution. [Windows App display settings](https://learn.microsoft.com/en-us/windows-app/display-settings).

Keep three separate concepts in implementation and preferences:

| Concept | Meaning |
|---|---|
| Remote resolution | The pixel dimensions Windows renders and RDP transports |
| Windows desktop scaling | How large Windows UI/text is rendered inside that resolution |
| Local fit/zoom | How the already-rendered image is placed in the Mac view |

Increasing local zoom alone cannot add remote detail. Increasing remote resolution alone can make Windows controls too small. Request suitable resolution and Windows scaling together; fit-to-window is a separate presentation operation.

## Geometry and backing pixels

Use the session **content view's** bounds in points and its current backing conversion to determine drawable pixels. Do not use the main screen's dimensions, include toolbar/title-bar space, assume all monitors are 2×, or multiply a size that is already expressed in pixels. Prefer `NSView.convertToBacking` and the view/window's actual backing state. [Apple backing conversion](https://developer.apple.com/documentation/appkit/nsview/converttobacking(_:)-3zors).

Keep these values explicit: content bounds in points, drawable pixels, requested remote pixels, active remote surface pixels, remote desktop scale, and the displayed image rectangle. Avoid a single ambiguous `scale` variable. For a Metal view, synchronize the drawable with backing dimensions while respecting its automatic-resize behavior; do not apply the factor twice. Native overlays use points; remote textures use pixels.

Example, not a hard-coded device profile: a 1440×900-point session area with a 2× backing store needs a 2880×1800-pixel drawable. A matching remote desktop with approximately 200% Windows desktop scaling keeps controls comfortably sized while retaining detail. This doubles both dimensions and quadruples pixel count versus 1440×900; actual compressed bandwidth depends on content and codec.

The backing size may differ from the physical panel resolution when macOS uses a scaled “Looks like” mode. Match the application's current backing geometry and let macOS perform its normal compositing. Do not claim a literal one-to-one panel-pixel mapping in every system display mode, or change the user's system resolution to get one.

## RDP negotiation and resizing

Use the installed FreeRDP settings and display-control channel APIs, not a custom protocol implementation. Relevant verified headers expose `FreeRDP_DesktopWidth`, `FreeRDP_DesktopHeight`, `FreeRDP_DesktopScaleFactor`, `FreeRDP_DeviceScaleFactor`, and display-control monitor-layout fields. Inspect matching source for their initialization/update paths before wiring the bridge.

Desktop scale and device scale have different valid values. The display-control protocol permits desktop scale in the 100–500% range, while device scale is restricted to 100, 140, or 180. **Do not send `DeviceScaleFactor=200` simply because the Mac backing factor is 2×.** Validate a supported pair and the host's resulting UI behavior. The layout also constrains dimensions, including even width and limits on each dimension; obey the negotiated server capabilities as well. [RDP display-control layout](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpedisp/ea2de591-9203-42cd-9908-be7a55237d1c).

Set an initial resolution and desktop-scale policy before connecting. Enable dynamic resolution when supported. Observe window resize, backing-property/screen changes, fullscreen transitions, and display removal. Moving one session between monitors belongs in first-release scope; spanning a session across several monitors can remain deferred.

Coalesce resize requests with a short debounce; begin around 150 ms and measure. Skip identical layouts and never send zero dimensions while minimized. Preserve the last valid surface during transitions. Track the requested geometry separately from the active geometry received from the server; switch rendering and input transforms coherently when the replacement surface is ready. Discard stale presentation work by generation and avoid allocating a new full-size texture for every intermediate drag event.

Some hosts or legacy Windows apps may not apply DPI changes immediately. Detect/report this accurately, retain a usable view, and offer a controlled reconnect when needed. Do not automatically log out Windows, kill remote applications, or modify server scaling policies. If the host rejects dynamic resolution or high DPI, show the actual mode and offer a supported fixed-resolution fallback.

## Pointer, cursor, and image quality

Map a local pointer into the displayed remote-image rectangle, then into the **active remote surface's** pixel coordinates. Respect letterboxing, cropping/panning if enabled, a flipped vertical axis where applicable, and the frame being displayed. For an image-normalized coordinate `u`, map to `floor(u * remoteWidth)` and clamp to the valid pixel range; apply the analogous transform for height. Ignore clicks in padding outside the image. Windows UI scale is not another multiplier on these RDP pointer coordinates.

Keep cursor image size and hotspot consistent with this transform and the chosen local/server cursor path. Test all corners, small text-selection targets, drag endpoints, context menus, and rapid moves between displays. Avoid a double-drawn pointer. A visually sharp image with offset clicks is a failed Retina implementation.

At settled matching resolution, sample the remote image without unintended extra scaling. Temporary fit during live resize may be softer, but it must converge after the server updates. Use a deliberate filter for explicit fit/zoom modes; nearest-neighbor everywhere is not a universal text-quality fix.

Use a consistent color space/pixel format through decode and presentation and test color fidelity. Compare small black and colored text, code syntax highlighting, thin lines, and grayscale edges. Assess supported AVC444 or other suitable graphics paths when chroma loss damages text; choose based on host compatibility and measured quality/latency. Do not add a local encode/decode roundtrip or claim that native resolution alone guarantees sharp text in a legacy non-DPI-aware Windows app.

## Performance policy

Reuse textures and staging buffers, update dirty regions where the renderer supports it, keep frame queues bounded, and avoid unnecessary redraws on a static desktop. Preserve immediate input and escape handling under Retina decode/upload load. Use frame pacing appropriate to actual updates; a 120 Hz Mac panel does not establish 120 fps remote content.

Budget memory from actual stride × height × live buffers plus codec/GPU resources. A tightly packed 3840×2160 BGRA surface alone is about 31.6 MiB; three copies are about 94.9 MiB before other resources. Report peak memory during resize as well as steady state. The existing 1080p budget is not automatically the correct budget for a larger Retina surface.

Keep **Optimize for Retina** as the default sharpness preference, with automatic Windows UI sizing and an optional explicit Windows text/UI scale. Offer an opt-in lower-resolution performance mode with its quality tradeoff stated. Do not silently drop to a blurry stream to satisfy a frame-rate target. If an adaptive mode is added later, show its effective resolution and keep native-quality mode available.

Profile the native-resolution path against Windows App before claiming parity. The current FreeRDP package's FFmpeg hardware-decode path remains disabled; rendering with Metal does not change that. Investigate the documented hardware-decoder experiment if profiling identifies decoding as the bottleneck. No extra library installation is required to specify Retina geometry or native display APIs.

## Acceptance matrix

All rows begin **NOT TESTED**. Use public/harmless remote content; do not store work screenshots in the repository.

| ID | Test | Pass condition | Result |
|---|---|---|---|
| R01 | Initial connection on the built-in Retina display | Backing-sized remote image, readable Windows UI, no client-induced persistent blur | NOT TESTED |
| R02 | Windowed ↔ fullscreen and live resize | Correct content area, final sharpness restored, no resize loop or unintended disconnect | NOT TESTED |
| R03 | Move the session between Retina and 1× external displays | Geometry/UI-scale policy adapts; cursor and capture remain correct | NOT TESTED |
| R04 | macOS default and scaled “Looks like” modes | Correct backing geometry; no double scaling or clipped remote area | NOT TESTED |
| R05 | Windows 100%, 150%, 200% scaling where supported | Readable UI and correct pointer; rejected/legacy behavior reported accurately | NOT TESTED |
| R06 | Corners, tiny targets, drag, text selection, letterboxing | Accurate clicks and cursor hotspot before/during/after resize | NOT TESTED |
| R07 | Small black/colored text, thin lines, scrolling | Sharpness and stability comparable with Windows App at equivalent settings | NOT TESTED |
| R08 | Native-resolution workload plus escape shortcut | Responsive input/release; measured latency/fps/CPU/memory, no hidden quality reduction | NOT TESTED |
| R09 | Sleep/wake, external display removal, repeated resize | Stable session state, no stale texture/input transform or memory growth | NOT TESTED |
| R10 | Host rejects display update / scale changes require reconnect | Honest effective mode, usable fallback, no automatic Windows logout | NOT TESTED |

Add meaningful unit tests when implementing the geometry code: point-to-remote transforms at 1×/2×, letterboxed and non-integral fit ratios, edge clamping, coordinate orientation, valid RDP layout construction, and stale resize-generation handling. Physical-display and visual-comparison rows still require real observation. Record unavailable external displays as not tested rather than passed.
