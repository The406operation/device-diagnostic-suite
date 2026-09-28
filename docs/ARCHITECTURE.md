# Architecture

## Boundaries

The macOS SwiftUI application owns the interface and local state. `DiagnosticStore` manages single-device sessions. `CampaignStore` manages paired roles, normalized runs, matched sessions, evidence attachments, and watcher control. `Command` launches installed tools with argument arrays, timeouts, and bounded returned output. It does not construct shell command strings from imported diagnostic text.

`Analysis` provides broad single-session event clues. `CampaignAnalysis` classifies timed cellular events, selects the latest observation by timestamp, and creates a bounded fault review. A normal serving-registration entry does not prove IMS recovery. Earlier IMS impairment remains contrary evidence.

The bundled Python scripts provide:

| Script | Function |
|---|---|
| `run_baseline.py` | Device-scoped metadata, safe diagnostic query, stationary selected logs, crash copy, and raw hash manifest |
| `parse_logarchive.py` | Validated archive entries, system log decoding, a five-minute review margin, normalized facts and events |
| `watch_sos.py` | Raw rolling history, candidate/user triggers, incident continuation, service-restored tail, freshness and clean stop |

`ExportPolicy` implements both export modes. Its Share-Safe schema is separate from internal storage models. Unknown fields, free text, source paths, raw event text, filenames, and identifiers do not enter that schema. Basic display redaction is a convenience and is not the Share-Safe privacy boundary.

## Local storage

The public application uses `~/Library/Application Support/Device Diagnostic Suite Public`. It does not migrate or write the private development application’s data store. Session data uses `sessions.json`. Campaign data uses `Campaign/campaign.json`, per-run `run.json`, normalized event JSON, raw evidence, and SHA-256 manifests. Watcher status and command files are local. There is no database server, telemetry service, account system, cloud synchronization, or automatic upload.

Fresh installs require explicit watcher arming. Arming enables automatic resume for that selected primary. Stop disables resume. A PID alone does not establish a healthy log stream; the interface also shows freshness and connection state.

## Evidence model

Every normalized observation has a field, value, basis, source, and timestamp. Basis separates device queries, device logs, Mac tests, user reports, and unavailable data. Markers record button-press time unless a note identifies an earlier action. UTC device-log decoding is distinct from Mac receipt time. A missing/private message remains a limit, not a healthy result.

The control and primary must have different device assignments. A matched session links their runs and stores conditions. It does not force equal radio technology, serving cell, provisioning, or radio conditions. The operator must report these differences when possible.

The release candidate changes labels, export privacy, tests, build packaging, and storage namespace. It retains capture commands, bounds, event classes, timing, and the three-domain fault model. No private campaign files or history seed the public app.
