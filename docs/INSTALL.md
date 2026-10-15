# Install Vela on a Mac

Experimental preview for Apple silicon (M-series) Macs. The deployment target is macOS 14 or later; development testing was performed on macOS 26.6.2. Older supported targets and other Mac models have not yet been independently verified.

## Camera requirements

The tested setup uses **two cameras**: the **MacBook Air built-in camera for gesture recognition** and a **separate stand-alone Logitech webcam for Zoom video**. The external webcam does not specifically need to be Logitech.

A single-camera setup **might work or might not**. Simultaneous camera sharing between Vela and Zoom has not been verified and is not guaranteed; it may depend on macOS, the camera/driver and the applications involved. This release automatically selects a built-in camera, so external-only setups without one are not currently supported.

## Download and install

1. Download the DMG from [the official GitHub Releases page](https://github.com/swihpi/vela-gesture-demo/releases).
2. Open the DMG and drag **Vela.app** onto the **Applications** shortcut.
3. Eject the Vela disk image. Open **Vela** from Applications or Spotlight.

## If macOS blocks the first launch

This experimental build is **ad-hoc signed, not Apple Developer ID signed, and not notarised by Apple**. A DMG does not remove that limitation. Apple has not checked this build for known malware.

If the warning says the developer cannot be verified or Apple cannot check the app, and you trust this project's release:

1. Attempt to open Vela from Applications.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the notice that Vela was blocked and choose **Open Anyway**.
4. Authenticate with Touch ID or your Mac password if requested, then confirm **Open**.

Use this app-specific exception only. Do not disable Gatekeeper globally or change system-wide security protections. If macOS reports malware or a damaged app, stop and report the exact message instead of bypassing it. Managed Macs may not allow exceptions.

See [Apple's official opening instructions](https://support.apple.com/102445).

## First run

- Allow **Camera** access for the local preview and gesture detection.
- In Vela's Settings, choose **Accessibility**, then enable Vela in **System Settings → Privacy & Security → Accessibility**. Complete the authentication sheet if one appears.
- Select your external webcam in Zoom. Vela uses the built-in MacBook camera separately.
- Start with **Practice**. Raise a hand into the dashed area, hold until the progress bar fills, and lower it below the area before repeating.
- Choose **Live** when ready to send commands to Zoom. **Paused** leaves the preview running without sending commands.

V sign and open palm toggle video. Thumbs up toggles microphone mute. Closed fist requests start/stop of Zoom computer recording. Recording requires Zoom permission and may show Zoom's own confirmation. Vela does not bypass or accept those prompts for you.

The red close button or Command-Q quits Vela and releases its camera. Yellow minimises; green resizes or enters full screen.

## Updates and removal

Quit Vela before replacing it in Applications. Because public preview builds are ad-hoc signed, a new build can require Camera or Accessibility approval again. This differs from the stable local certificate used during development.

To remove it, quit Vela and move Vela.app from Applications to the Trash. You can also remove its Camera and Accessibility permissions in System Settings.

## Verify the download

The release includes `SHA256SUMS.txt`. With the DMG and checksum file in the same directory, advanced users can run `shasum -a 256 -c SHA256SUMS.txt`. A checksum checks that a download matches the release; it is not Apple notarisation or an independent security review.
