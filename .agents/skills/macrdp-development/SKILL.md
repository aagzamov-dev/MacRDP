---
name: macrdp-development
description: Implement and verify MacRDP's native macOS keyboard capture, FreeRDP session bridge, and rendering. Use for development in this project, including capture failures and Windows App performance comparisons.
---

# MacRDP development

Read [requirements](../../../docs/REQUIREMENTS.md) and [setup status](../../../docs/SETUP-STATUS.md). Run the existing doctor and dependency probe before diagnosing missing libraries.

For input work, use [the keyboard acceptance plan](../../../docs/KEYBOARD-TEST-PLAN.md). Prove the release path before exclusive capture, and test the actual Windows action before calling a shortcut supported. An event arriving locally does not establish RDP delivery; an SDL grab flag returning success does not establish interception of macOS shortcuts.

Build around public AppKit/CoreGraphics APIs and an explicit local/captured state. Gate filtering on the active session surface, release before dialogs or focus changes, and release tracked remote keys on every exit. Keep escape evaluation off the network/rendering path. Do not use global key logging as a diagnostic shortcut.

Inspect the pinned FreeRDP headers and matching upstream implementation before adding bridge calls. Keep one owner for each session and serialize input with lifecycle teardown. Avoid double delivery from an event tap plus AppKit/SDL handlers. Keep certificate decisions and credential entry outside capture.

For session geometry or rendering, read [the required Retina specification](../../../docs/RETINA-DISPLAY.md). Validate backing-sized output, Windows DPI settings, cursor transforms and display-change transitions together. A fast lower-resolution stream does not satisfy the Retina requirement.

For performance work, use [the benchmark procedure](../../../docs/PERFORMANCE.md). Compare identical server/network/resolution conditions, profile the first bottleneck, and verify the actual decoder/presentation path. Do not report negotiated codec support as proof of hardware decoding.

Implement the next incomplete milestone, run relevant builds/tests, and record observed results separately from intended behavior. Public-API capture and gesture limitations are findings to report, not reasons to silently add private APIs or alter global macOS preferences.
