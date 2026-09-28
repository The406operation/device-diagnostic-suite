#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
output="${1:-$PWD/dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
build_root="$(mktemp -d "${TMPDIR:-/tmp}/device-suite-build.XXXXXX")"
trap 'rm -rf "$build_root"' EXIT
swift build -c release --scratch-path "$build_root/swift" -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."
bin_dir="$(swift build -c release --scratch-path "$build_root/swift" --show-bin-path)"
bundle="$output/Device Diagnostic Suite.app"
if [ -e "$bundle" ]; then
    echo "Output app already exists. Choose an empty output directory." >&2
    exit 1
fi
python3 - "$bin_dir/DeviceDiagnosticSuite" "$bundle" "$(cat VERSION)" <<'PY'
import plistlib
import shutil
import sys
from pathlib import Path
binary, bundle, version = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
exe = bundle / 'Contents/MacOS/DeviceDiagnosticSuite'
exe.parent.mkdir(parents=True)
shutil.copy2(binary, exe)
resources = bundle / 'Contents/Resources'
resources.mkdir(parents=True)
for source in sorted(Path('Sources/DeviceDiagnosticSuite/Resources').glob('*.py')):
    shutil.copy2(source, resources / source.name)
info = {
    'CFBundleName': 'Device Diagnostic Suite',
    'CFBundleDisplayName': 'Device Diagnostic Suite',
    'CFBundleExecutable': 'DeviceDiagnosticSuite',
    'CFBundleIdentifier': 'org.devicediagnosticsuite.app',
    'CFBundleVersion': '1',
    'CFBundleShortVersionString': version,
    'CFBundlePackageType': 'APPL',
    'LSMinimumSystemVersion': '15.0',
    'NSHighResolutionCapable': True,
}
(bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
/usr/bin/codesign --force --sign - --timestamp=none "$bundle"
/usr/bin/codesign --verify --deep --strict "$bundle"
/usr/bin/ditto --norsrc -c -k --keepParent "$bundle" "$output/Device Diagnostic Suite.app.zip"
echo "Built and locally signed the app in the requested output directory."
