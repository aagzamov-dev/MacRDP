# GitHub updates without an Apple Developer account

MacRDP uses Sparkle 2.10.0, a pinned framework downloaded by `scripts/fetch-sparkle.sh` with SHA-256 verification. The app checks the signed feed at:

`https://github.com/aagzamov-dev/MacRDP/releases/latest/download/appcast.xml`

The Updates page is available from Settings and the menu-bar icon. Automatic checks are enabled by default; installation is user initiated. Checks wait while a Windows connection is active. If a connection starts after an update check, relaunch is deferred until disconnect.

## Signing

The update-signing key was generated under the Keychain account `uz.macrdp.updates`. The private key remains in Keychain; only its public key is in `Resources/Info.plist`. Back up that private key securely with Sparkle’s `generate_keys` tool before moving to another Mac. Never commit an exported key or paste it into chat. Replacing the public key breaks the trust chain for existing installations.

No Apple Developer account is required. `scripts/setup-signing.sh` creates one self-signed code-signing identity in the login Keychain, pins its public certificate in `config/MacRDP-Signing.cer`, and trusts that certificate for **code signing only** in the user trust domain. Builds select its fingerprint and fail instead of falling back to ad-hoc signing. Debug, Release, and packaged apps keep the same certificate-based designated requirement and `uz.macrdp.app` identifier. The certificate’s private key is never stored in the repository. Back up this identity securely through Keychain Access before moving to another build Mac; restore it instead of generating another certificate.

**Stable signing alone did not eliminate Keychain prompts on this macOS.** A test with two different executables and identical certificate-based requirements still failed a noninteractive credential read after the update. The shipping app therefore uses a fixed signed helper, `Contents/Helpers/MacRDPKeychain`, for credential access. It retains the same binary hash across app releases. `Resources/KeychainHelper/SHA256SUMS.txt` pins the helper and its sources. Builds copy it without re-signing or recompiling it and fail if the pinned files change. Deliberately updating the helper requires a reviewed rebuild and another one-time user authorization.

The app verifies the helper’s signature before sending a request; the helper verifies its running parent is `uz.macrdp.app`, signed with the same certificate. Requests and responses use private pipes, never command-line passwords or diagnostic logs. Only the existing `uz.macrdp.credentials` service and `app-lock` / `pc-UUID` accounts are supported. Existing records are not renamed, deleted, or exported. When upgrading from the old direct-access build, macOS may ask once **per existing item** to allow MacRDPKeychain. Choose Always Allow. Future app updates retain the unchanged helper and its authorization. Keep using the installed Applications copy.

Run `scripts/test-signing.sh` to validate two changed app builds against a disposable synthetic Keychain credential through the same helper, with Keychain interaction disabled. The test also rejects an untrusted caller and checks the pinned helper hash. It never reads production credentials. The older direct-signing C fixture remains as documentation of the platform limitation.

Sparkle’s separate Ed25519 signatures protect the archive and feed. Self-signing does not notarize the app or bypass Gatekeeper; the first install may require Open Anyway in macOS Privacy & Security. Accessibility is separate and remains handled by the app’s permission setup.

## Build a local package

```sh
./scripts/setup-signing.sh   # Once on this build Mac; reuse the original identity afterward.
./scripts/package-release.sh 0.2.1
```

This builds Release, bundles the linked Homebrew libraries and their available license notices, checks the app signature, creates the update ZIP, signs the appcast, and creates an unsigned disk image containing the signed app. The output is `build/releases/0.2.1/`, including a signed ZIP, signed appcast, drag-to-Applications DMG, and checksums. It does not upload anything. An existing version folder is never overwritten. Versions must increase; the default numeric build number is a UTC timestamp.

The app still requires macOS 27+ and Apple Silicon because of the installed FreeRDP dependencies. Packaging does not establish compatibility with older macOS versions. Keep the deployment target aligned with bundled libraries.

## Publish an update

Commit and push reviewed changes to `main`, then:

```sh
./scripts/publish-release.sh 0.2.2
```

The script verifies the clean commit matches `origin/main`, runs the behavioral/native/RDP suites, packages if necessary, verifies the package belongs to that clean commit, and uploads a **draft** GitHub Release with the signed zip, installer DMG, checksums and `appcast.xml`. Review and publish the draft on GitHub. Publishing makes that release available through the existing in-app update feed; no GitHub token is stored in the app and no separate web server is required.

Every stable release must include both the matching signed archive and `appcast.xml`; GitHub’s automatic source archives alone are not installable updates. Do not edit the signed appcast after generation. Keep the feed attached to the latest stable release. Use a new version for another release rather than replacing published archives.

The old 0.1.0 build has no updater. Install the first updater-enabled version once, then subsequent releases can be installed from inside MacRDP. End-to-end installation between two published GitHub versions still needs a two-version acceptance test.

## Installing the prepared local version

Open `build/releases/0.2.1/MacRDP-0.2.1.dmg`, quit the old MacRDP process, and drag MacRDP onto Applications. Replace the old app and launch the Applications copy. This replaces the app bundle only; saved PC profiles, PIN records and passwords stay in their existing locations. The current local package was built with uncommitted implementation changes, so publishing it is intentionally blocked. Commit and push the reviewed sources, then use a new release version (for example 0.2.2) with `publish-release.sh` to build and upload a draft from a clean commit.

## First public release

Version 0.2.2 is the first GitHub release. It is rebuilt from committed source, rather than uploading the earlier local 0.2.1 package. Install the DMG from the GitHub release once; future stable releases use the same update feed and signing keys.

## Disk-image packaging correction — 0.2.3

The disk image itself is now unsigned. The earlier local-certificate signature caused Gatekeeper to assess the container on opening; Apple specifies Developer ID Application identities for signed disk images. The app, fixed credential helper, and Sparkle updates retain their existing signatures. First launch of the app still requires user approval without notarization. Validate the downloaded image on a clean Mac; a local mount does not establish Gatekeeper acceptance.

## Inline updates and restart — 0.2.6

Sparkle now uses a custom native user driver in Settings → Updates for checks, progress, cancellation, errors and install/restart. Signature verification and archive installation remain handled by Sparkle. Install/restart dismisses local sheets and shuts down input before requesting app termination. The app delegate explicitly returns terminateNow. Manual restart launches a small system-shell waiter with positional arguments; it reopens the app only after the current process exits and aborts after 30 seconds if it does not. No app process is forcibly killed. Existing duplicate copies from older versions must be quit once.

The modal termination policy is explicitly disabled for MacRDP's own sheets. AppKit can refuse a quit request before calling applicationShouldTerminate when a sheet has preventsApplicationTerminationWhenModal enabled. See [Apple's window termination guidance](https://developer.apple.com/videos/play/wwdc2026/289/) and the installed NSWindow header. This was reproduced in the isolated native process fixture.
