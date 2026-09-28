# Device Diagnostic Suite

**Local macOS diagnostics for iPhone**

A local macOS application for connected iPhone diagnostics, matched two-phone comparisons, and SOS capture. Native SwiftUI interface. Release candidate **0.3.0-rc.2**.

This project is independent. Apple and carriers do not sponsor, endorse, or operate it. Product names identify supported interfaces and diagnostic sources.

## What it does

- Device Overview: reported hardware type, iOS/build, modem firmware, SIM readiness, battery, storage, and pairing status.
- Live Logs: accessible CommCenter, CoreTelephony, and related events.
- Cellular/SOS: classified registration, IMS (Internet Protocol Multimedia Subsystem), modem, SIM, call, and app data-path events.
- Network Tests: a clearly labeled Mac HTTPS check. It does not measure iPhone cellular service.
- Crash & Analytics: copy accessible reports while retaining the phone originals.
- Sysdiagnose Import: bounded text/member inspection, logarchive decoding, and raw evidence attachment. Import does not perform a complete Apple specialist analysis.
- Event Timeline and Baseline/Comparison: timestamps, user markers, normalized observations, and repeatable matched conditions.
- Paired Devices: a primary device under test and a stable control. Compare available fields without treating the control as proof of cause.
- SOS Watcher: preserve rolling logs before a fault, then during and after the fault. Confirm candidate log triggers against the phone display.
- Private Diagnostic Export and Share-Safe Export. See [Privacy](docs/PRIVACY.md).

## Build and test

Requirements: macOS 15 or later, Xcode with Swift 6, and Python 3.9 or later. The clean local verification used Xcode 27 and Swift 6.4 on Apple Silicon. Other toolchains and Intel hardware require separate verification.

```sh
swift test --scratch-path /tmp/device-suite-tests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s PythonTests -v
python3 scripts/publication_scan.py .
./build-app.sh /tmp/device-suite-app-output
```

Choose an empty app output directory. The build makes a local ad hoc signed `.app` and ZIP. This signature needs no account, certificate, provisioning profile, or protected entitlement. The build is not notarized for public binary distribution. See [Build](docs/BUILD.md) for clean-path verification and reproducibility limits.

For connected-device capture, install `libimobiledevice` separately with Homebrew. It is not needed for offline tests or compilation:

```sh
brew install libimobiledevice
```

No Swift package, Python package, third-party binary, or diagnostic data is bundled. See [Dependencies and licenses](docs/DEPENDENCIES.md).

## First capture

1. Connect the iPhone by USB. Unlock it and accept the phone’s Trust prompt if requested.
2. Open the built app. Review the device role before each capture.
3. For a comparison, assign Control and Primary to different phones. Record the same location, time window, Wi-Fi state, and cellular state. Run the control baseline first.
4. Arm the SOS watcher explicitly before the fault. Keep the Mac awake and the primary phone connected. Use a visible SOS marker if the logs do not expose the transition.
5. Review facts, inference, confidence, contrary evidence, and uncertainty. Save a Private Diagnostic Export locally. Use Share-Safe Export for a review packet and inspect it before sharing.

The suite does not place calls, send SMS, transfer eSIMs, change carrier provisioning, reset settings, erase devices, or restore firmware. Users perform any separately approved phone action and record a marker. Developer Mode is not required for basic paired queries. Some Xcode services require it; the suite reports failures and does not enable it. See [Workflows](docs/WORKFLOWS.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Diagnostic sources](docs/DIAGNOSTIC_SOURCES.md)
- [Limits and fault isolation](docs/LIMITATIONS.md)
- [Privacy and export schemas](docs/PRIVACY.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Release runbook](docs/RELEASE.md)

Only synthetic fixtures belong in this repository. Do not attach raw sysdiagnose files, raw logs, crash reports, identifiers, credentials, private exports, or private screenshots to an issue.

## License

This project uses the [MIT license](LICENSE). External tool licenses remain separate. See [Dependencies and licenses](docs/DEPENDENCIES.md).
