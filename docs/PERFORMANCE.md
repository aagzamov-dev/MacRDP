# Windows App comparison and performance plan

Windows App-level responsiveness is a product target. No performance parity has been measured yet. The Homebrew FreeRDP build has FFmpeg hardware acceleration disabled; keep that fact attached to all baseline results.

## Comparable conditions

Compare **Windows App**, the installed **SDL FreeRDP client**, and **MacRDP** sequentially against the same Windows host/session. Avoid simultaneous connections that change session state or workload. Keep server workload, VPN, network path, monitor, power mode, resolution, scaling, color depth, and test content comparable. Record actual codec/transport negotiation where each client exposes it; otherwise mark unknown.

Use 1920×1080 at 100% scaling for an initial engine check. The user's actual Retina backing resolution and comfortable Windows UI scale are a required primary comparison, with Windows App's Retina optimization enabled. Record Mac content size in points, backing size in pixels, active remote resolution, Windows scale, and local fit mode. Follow [RETINA-DISPLAY.md](RETINA-DISPLAY.md), including default/scaled macOS display modes and movement between Retina and 1× displays when available. Use the same remote browser/editor/text and local screen brightness/power conditions. Do not run bandwidth stress or change Windows policies on a work PC without a concrete reason and appropriate authorization.

## Workloads

1. Static desktop for two minutes: idle CPU, memory, network traffic, wakeups.
2. Five minutes of typing and caret movement in a harmless editor document.
3. Repeated scrolling in the same text-heavy page/document and dragging a window.
4. A repeatable 30/60 fps motion clip only if useful for this user's workload.
5. Full-screen/resizing and capture/release under native Retina load; verify cursor alignment and escape responsiveness.
6. Compare small black/colored text, thin lines and code at equivalent Retina settings; record sharpness and compression artifacts alongside speed.
7. Thirty minutes of mixed interaction, including disconnect/reconnect, for leaks and stability.

Run each short comparison at least three times; report median and spread. Use Instruments Time Profiler/Allocations and app counters for decode/presentation queues. Use Metal tools only when the app actually uses Metal. For end-to-end key-to-pixel latency, an external high-frame-rate camera or a carefully designed synchronized instrumented test is more credible than subtracting unrelated timestamps. Record capture overhead if measuring through screen recording.

## Initial acceptance targets

These are engineering targets, not measured facts:

- Escape changes local capture state within 100 ms during normal load; it never waits for network I/O. macOS Space animations may take longer, but interception must stop first; toggling input must preserve the session window/full screen.
- At 1080p, sustain smooth interactive scrolling and approach 60 fps **when the host actually supplies that rate**. Do not report display refresh frequency as delivered remote fps.
- At the actual Retina resolution, require comparable text clarity and record delivered fps, frame-time spread and interaction quality against Windows App; an easy 1080p pass is insufficient.
- Median input latency no more than 20 ms worse than Windows App under the same measured conditions, including native Retina; show p95 and method, not just a single best value.
- Avoid a presentation backlog exceeding two complete frames. Preserve the latest applied desktop state while coalescing display work.
- Target idle CPU below 5% of one core on this Mac and steady memory below 300 MiB for the basic 1080p session; revise with explicit measured reasoning if required by the actual codecs and buffers.
- For Retina, derive a separate memory budget from buffer dimensions/stride and live CPU/GPU/codec allocations; record resize peaks and bandwidth. Do not apply the 1080p RSS target blindly to a much larger surface.
- No increasing memory/worker count across ten connect/disconnect cycles or repeated resolution changes.

Treat CPU, memory, network and visual quality together. A lower frame rate, lower resolution, or software cursor workaround is not performance parity if the comparator uses better quality.

## Optimization sequence

First establish correct frame delivery and collect profiles. Fix redundant full-buffer copies, blocking main-thread work, per-frame allocation, busy waiting, and unbounded queues before changing codecs. Keep keyboard processing independent of rendering congestion.

Then evaluate modern RDP graphics/H.264 variants and dynamic resolution with the host. If decoding is the bottleneck, inspect FreeRDP 3.32.2's actual `WITH_FFMPEG_HWACCEL` implementation and FFmpeg device support. Build a pinned version into a project-local prefix with supported flags, preserving the working Homebrew baseline. Verify VideoToolbox device/decoder initialization and runtime use; compare output correctness, CPU and latency. Having a compiler flag, framework, codec advertisement, or FFmpeg capability list is not enough.

Metal presentation and hardware video decoding solve different costs. A software-decoded BGRA image uploaded to Metal still has decoding and copy costs. Do not promise zero-copy or change to an entirely different engine without evidence.

## Results template

| Client/build | Remote pixels / Windows scale / Mac backing | Codec/transport | Decoder | Median/p95 latency | Delivered fps | CPU/RSS | Sharpness / notes |
|---|---|---|---|---|---|---|---|
| Windows App | Not measured | Unknown | Unknown | — | — | — | Baseline pending |
| SDL FreeRDP 3.32.2 | Not measured | Unknown | FFmpeg HW path compiled OFF | — | — | — | Baseline pending |
| MacRDP | Implemented; native-resolution benchmark pending | Unknown | Software decoder; HW path OFF | — | — | — | Display-link presentation, background snapshots, dirty-region bridge copies |

Store only sanitized aggregate results. No production screen recordings, typed content, or passwords in the repository.

## Implementation checks — 2026-10-24

The deterministic bridge test now verifies a 32×32 update copies 4,096 bytes into the bridge snapshot instead of the complete 6,400,000-byte 1600×1000 surface. The first frame and resolution changes still copy the full surface. This measures the bridge copy decision only, not end-to-end FPS, decoding cost, or total memory bandwidth. Presentation still takes a complete snapshot, but on a dedicated background queue with bounded reusable buffers.

The displayed FPS counts new frames drawn by the native view, sampled about once per second; it is not the panel refresh rate or a measurement of key-to-pixel latency. Presentation is skipped on an inactive Space or occluded/minimized window. Consecutive mouse moves coalesce while button/keyboard order remains intact.
