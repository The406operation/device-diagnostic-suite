# Dependencies and license review

## Application and build inventory

| Component | Use | Bundled in this source candidate? | License/source |
|---|---|---|---|
| SwiftUI, AppKit, Foundation, Combine, CryptoKit, Darwin | Native UI, files/processes/network, hashes, process status | Imports only; no Apple SDK/framework files | Apple SDK/system components; applicable [Apple agreements](https://developer.apple.com/support/terms/) |
| XCTest | Offline tests | Test imports only | Apple toolchain test framework |
| Swift compiler/SwiftPM/runtime | Compile/package application | No compiler/SDK source or binaries | [Apache-2.0 with Runtime Library Exception](https://www.swift.org/legal/license.html) for the open-source Swift components |
| Python standard library | Capture, parser, tests, packaging/scan | Project scripts only; no Python runtime/packages | [PSF-2.0 and incorporated notices](https://docs.python.org/3/license.html) |
| Xcode `devicectl`, macOS `log`, `tar`, `ditto`, `codesign`, `unzip` | Installed command-line interfaces | No binaries | Host tools under their respective Apple/upstream terms |
| Homebrew | Optional installation of capture tools | No code or binaries | [BSD-2-Clause](https://github.com/Homebrew/brew/blob/main/LICENSE.txt) for brew; formula packages have their own licenses |
| `libimobiledevice` 1.4.0 tools | Separate processes: `idevice_id`, `ideviceinfo`, `idevicepair`, `idevicesyslog`, `idevicecrashreport`, `idevicediagnostics` | No library linkage, source, or tools bundled | LGPL-2.1-or-later in each used tool’s reviewed release source header |
| `actions/checkout` v4.2.2 | Prepared CI only, pinned commit | Workflow reference only | [MIT upstream license](https://github.com/actions/checkout/blob/v4.2.2/LICENSE) |

There are zero external Swift Package dependencies and zero Python package dependencies. No Xcode project, third-party archive, pairing record, signing identity, certificate, provisioning profile, entitlement file, vendored binary, or public app binary is part of the candidate.

The libimobiledevice repository contains more than one license. The used tool files, rather than a repository-wide label alone, were checked: [device info](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/ideviceinfo.c), [device ID](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/idevice_id.c), [pairing](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/idevicepair.c), [syslog](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/idevicesyslog.c), [crash copy](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/idevicecrashreport.c), and [diagnostics](https://github.com/libimobiledevice/libimobiledevice/blob/1.4.0/tools/idevicediagnostics.c).

## External Homebrew runtime closure

The inspected libimobiledevice formula uses these external libraries. They are not shipped by this candidate. Exact resolved versions can change; the JSON inventory records the reviewed versions and source links.

| Component | Reviewed version | Formula license |
|---|---|---|
| libimobiledevice-glue | 1.3.2 | LGPL-2.1-or-later |
| libplist | 2.7.0 | LGPL-2.1-or-later |
| libtasn1 | 4.21.0 | LGPL-2.1-or-later |
| libtatsu | 1.0.5 | LGPL-2.1-or-later |
| libusbmuxd | 2.1.1 | GPL-2.0-or-later AND LGPL-2.1-or-later, for different parts |
| OpenSSL | 3.6.4 | Apache-2.0 |
| ca-certificates | External trust-store data | MPL-2.0; inspect the installed formula/version before redistributing |

This app does not install or distribute a separate usbmuxd daemon. Homebrew’s external tool dependency closure is not the app’s linked dependency closure. OpenSSL’s certificate store is not copied into an export or bundle.

## Redistribution obligations

The proposed MIT notice applies only to project-owned code and synthetic fixtures after owner approval. It cannot replace Apple SDK terms or any dependency license. Users install dependencies independently. Calling an installed program as a separate process does not copy its code into this publication set.

If a future distributor bundles libimobiledevice tools/libraries, review the exact versions and complete dependency closure again. Retain applicable notices and licenses; provide required corresponding source/modifications and satisfy LGPL relinking/replacement requirements where applicable. GPL-covered parts need their applicable source obligations. OpenSSL and trust-store redistribution carry their own notice/license duties. Do not assume an MIT project notice covers a Homebrew bottle.

No Apple framework, Xcode tool, SDK, or Python runtime is redistributed here. Review vendor terms separately before a packaged-runtime distribution. The Swift runtime exception addresses compiler/runtime portions embedded by compilation; it does not relicense Apple SDK components.

## Recommended project license

**MIT** is recommended for project-owned application code, scripts, documentation, tests, and newly authored fixtures. It is short, permits reuse/modification/distribution, and fits a source project with no embedded copyleft dependency. Its notice must accompany copies. It provides no express patent grant; Apache-2.0 would be an alternative if that grant is an owner requirement. The owner’s preference is not assumed.

`LICENSE.proposed` is a draft for owner adoption. The source lineage showed no existing project license or copied third-party source notice. Ownership and license approval are publication decisions, not established by build tests. This audit does not authorize publication.
