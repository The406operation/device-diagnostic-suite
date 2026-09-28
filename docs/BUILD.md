# Build and verification

The application is a Swift Package executable. No Xcode project, external Swift package, signing configuration, or local developer-team value is required. Test fixtures are SwiftPM test resources. Application Python resources are copied explicitly by `build-app.sh`; they do not rely on a generated resource accessor with an absolute development path.

## Clean verification

Copy the candidate to a new temporary directory. Copy file bytes without extended attributes. Do not include private history or data. Run:

```sh
swift --version
xcodebuild -version
python3 --version
python3 scripts/publication_scan.py .
swift test --scratch-path /tmp/device-suite-clean-tests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s PythonTests -v
./build-app.sh /tmp/device-suite-clean-app
```

Use fresh scratch/output paths when repeating a clean verification. A preexisting app output causes the build to stop. Compilation and tests do not need a connected phone, Homebrew, credentials, or Internet package resolution. The script builds for the host architecture. Intel and universal binaries are not claimed as verified by an Apple Silicon run.

The script uses a new scratch directory, copies the executable and Python resources, creates a generic Info.plist, signs ad hoc, verifies the signature, and archives the app. It performs no installation and does not open the app. The output bundle is outside the publication set.

## Reproducibility definition

The source ZIP has fixed member order, timestamps, and permissions. `PUBLICATION.json` names every published file and its SHA-256. The ZIP itself has a separate audit hash. The same exact source ZIP can be generated again.

A clean build must compile and pass the same offline checks without the private workspace. Byte-identical signed app binaries are not promised across Xcode/SDK versions or host architectures. Toolchain upgrades can change generated code and signing bytes. This candidate publishes source only.

## Runtime dependencies

Xcode supplies `xcrun devicectl` and the system Python entry point used by capture routines. A working Python 3 is required. Homebrew tool paths on Apple Silicon and Intel are supported, plus standard system paths. The application calls installed tools; it does not copy them into the bundle. Device service availability depends on the installed tool version and iOS compatibility.

## CI

The prepared GitHub workflow runs offline privacy gates, Swift tests, Python tests, and a release app build. It pins checkout to a reviewed commit, uses read-only repository permissions, disables persisted checkout credentials, and selects Xcode 26.6 on macOS 26. It uploads no artifacts and has no release or deployment step. The prepared workflow has not been executed on GitHub. The local clean verification is recorded separately.
