MacRDP now prefers VideoToolbox H.264 decoding on supported Macs, with software fallback when hardware initialization or format negotiation is unavailable. Decoder status appears in session diagnostics. Rendering keeps Retina quality and avoids redundant layout and frame-scheduling work.

- Per-PC VPN selection waits for you to connect the VPN manually; MacRDP never starts or stops it.
- Floating session controls stay available, with an icon-only Release to Mac button and configurable positioning.
- Unlock and reset the app PIN using Mac authentication.
- Includes clipboard, connection handling and session settings improvements. Experimental Dock hiding has been removed.

Synthetic H.264 hardware decoding and forced software fallback were verified on an M2 Pro. Live FPS gains depend on the server, network and workload; broad AVC444 and device-loss coverage is still pending. The existing software test build remains available locally for comparison.

Install the DMG or use the app updater. This release retains the production app identity and credential helper. It is locally signed, not Apple-notarized.
