# Building Vela

Apple silicon Mac, Swift 6 toolchain and macOS SDK required. The project has no third-party package dependencies. The minimum deployment target is macOS 14; this is not a statement of verified compatibility across every target version.

## Logic checks

```sh
swift run --disable-sandbox GestureChecks
```

The framework-free runner checks classification, hold/release timing, tracking gaps, mapping validation, local persistence, deletion/undo and preset migration. It does not replace live camera and Zoom tests.

## Reproduce the public DMG

```sh
./script/package_dmg.sh
```

The script builds an optimised Apple-silicon executable, maps source paths out of the build, strips debug symbols, creates a self-contained app with an icon, ad-hoc signs it and packages it with an Applications shortcut and installation instructions. It runs `hdiutil verify` and produces a checksum. Output is in `outputs/release/`.

Ad-hoc signing is not Apple Developer ID signing or notarisation. The first launch may require an app-specific Gatekeeper exception; updates can require renewed privacy approvals.

## Local development with a stable certificate

For repeated development, use your own local code-signing certificate. The private key must remain in your Keychain. Configure its name or fingerprint through `VELA_SIGNING_IDENTITY`, or an ignored project-local `.vela-signing-identity` file.

```sh
VELA_SIGNING_IDENTITY="Your certificate name" ./script/build_and_run.sh
```

The script stages and verifies the new bundle, stops the old process before replacing it, and keeps a local rollback copy. It refuses to publish when process inspection is blocked. It deliberately does not silently fall back to ad-hoc signing for iterative development, because that changes the code identity used by privacy approvals.

`./script/build_and_run.sh --install` also updates `/Applications/Vela.app`. `./script/install.sh` installs an already-built bundle. Neither script reads or exports your private key or account credentials.

## Layout

- `Sources/GestureCore`: gesture rules, temporal gating, mapping models and persistence.
- `Sources/GestureChecks`: deterministic checks.
- `Sources/Vela`: capture, UI, app lifecycle and Zoom automation.
- `Support/Info.plist`: public bundle metadata.
- `docs`: landing page and installation guide.

## Release acceptance still worth doing

Test the actual downloaded DMG in a fresh user account or on another Mac: Gatekeeper, Camera and Accessibility setup, both cameras active, all video/audio toggles, thumbs-up raise/lower hand, recording start/stop with and without permission, red-button quit and subsequent relaunch. Do not mark those checks passed from a successful build alone.
