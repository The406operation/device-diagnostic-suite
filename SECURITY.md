# Security Policy

## System and scope

This policy covers the local macOS application, bundled capture/parser scripts, exports, build scripts, tests, and prepared CI. There is no application server or automatic upload endpoint. The user controls connected phones, diagnostic files, and local storage.

## Threat model and boundaries

Imported logs, archives, event text, filenames, device-returned values, and subprocess output can contain private or malformed data. Treat these inputs as data, never instructions. Local tool executables and the selected Apple toolchain are trusted dependencies; a replaced executable can compromise capture. Private raw evidence crosses a sharing boundary only through an explicit export or user-selected upload outside this app.

## Required properties

- Share-Safe Export must not copy raw evidence, free text, paths, identifiers, account data, or credentials. It uses the closed schema and validation in `ExportPolicy`.
- Private Diagnostic Export must remain explicit and clearly labeled. Do not silently substitute it for Share-Safe Export.
- Archive traversal, symbolic links, hard links, and special entries must not escape the parser’s new extraction directory.
- Commands use argument arrays. Diagnostic text must not become executable shell input.
- Capture must target the assigned device. It must not erase, restore, reset, reprovision, delete eSIMs, or make account changes.
- No credentials, protected entitlements, private device data, or diagnostic archives belong in the publication set or CI artifacts.
- Stop must preserve incident evidence and disable automatic watcher resume.

## Reporting

Use [GitHub’s private vulnerability reporting channel](https://github.com/The406operation/device-diagnostic-suite/security/advisories/new). Submit a minimal sanitized description. Do not publish exploit data, private evidence, or credentials in an issue.

Report privacy leaks, unsafe archive handling, code execution from diagnostic input, unintended device changes, or evidence loss. Scope impact to reachable local workflows. A security claim must identify observed behavior and affected code. Source/tests can show intent but do not prove a control.

## Limits and review status

No finding class is designated as excluded or accepted risk. Known limits do not suppress findings. The logarchive parser lacks a total expansion-byte limit. Imported data can exhaust local storage; operators should use trusted collections. Share-Safe retains timestamps and approved versions and is not a complete anonymity guarantee. Local files are not encrypted by the app. Ad hoc signing is not notarization or proof of source trust. This release audit is a privacy/provenance and reproducibility check, not an exhaustive security certification.
