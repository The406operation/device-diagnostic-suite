# Privacy and exports

## Local data

Raw diagnostics can contain device and subscriber identifiers, phone numbers, account information, Wi-Fi details, addresses, locations, app activity, messages, and credentials. Keep the Mac account and local storage protected. The app has no automatic upload or telemetry. The optional Mac HTTPS test contacts the documented Apple test endpoint when the user runs it; capture alone does not run this request.

Basic single-session display/event redaction uses patterns and can miss private data. Campaign and watcher raw evidence is deliberately retained locally. Local storage is not a public sharing format. This candidate contains only reusable code and newly written synthetic fixtures.

## Export modes

| Mode | Includes | Appropriate use |
|---|---|---|
| Private Diagnostic Export | Full retained run/session metadata; campaign run folder with raw evidence; associated imported evidence | Local preservation and a separately authorized private support channel |
| Share-Safe Export | Approved normalized values, observation basis/time, event and action types/times, coarse counts, comparison results, recomputed conservative assessment | A reviewed sanitized packet; no raw evidence |

Private campaign export copies the selected run, not every device’s store or unrelated files. Watcher incidents must first be attached to a run to include them. Imported symbolic links cause private export to stop. Session exports retain the JSON, report, and spreadsheet-safe event CSV outputs. Share-Safe CSV contains only event types and timestamps. Private session export includes all retained session data, but cannot recover text removed during earlier display/event processing. The app does not collect pairing records or credentials for an export.

Share-Safe Export never carries free-text titles, notes, locations, outcomes, errors, source names, filenames, raw summaries, event detail, raw files, evidence paths/hashes, device identifiers, device names, or arbitrary field values. Device/line identifiers are omitted. Roles are generic Primary and Control. Unknown observation fields are omitted. Approved values use per-field grammar, numeric ranges, or fixed choices. Carrier-bundle identity is omitted; its version can remain. Comparison exposes equality/difference only for approved field classes.

Exact observation and action timestamps remain. Model type and software/build versions remain when valid. These can identify an incident through context. Share-Safe does not mean anonymous against every correlation attack. Inspect the packet before sharing. Use synthetic dates/examples in public issues when possible.

## Share-Safe schemas

`share-safe-session-v1`: session kind and interval, constrained product/iOS/build/modem fields, event type/time, and counts. No session identifier or imported filename is exported.

`share-safe-campaign-v1`: generic role and interval, fixed status/error count, approved observations, event/action types and times, evidence file count, conservative assessment, and per-field Matches/Differs/Unmeasured comparison. A missing/private/unrecognized value is not a healthy result. Comparison result describes recorded values, not the cause.

## Automated gates

Tests inject synthetic owner/device names, host paths, phone/email contacts, UDID/serial/IMEI/EID/ICCID, account information, Wi-Fi identifiers, IP addresses, coordinates, pairing/signing/provisioning records, key/certificate text, API token, password, and Apple Account values into every free-text channel. Tests inspect serialized session and campaign payloads plus a real generated ZIP. Private mode must retain the synthetic raw evidence; Share-Safe mode must omit it. A second pattern check refuses common sensitive forms before writing Share-Safe output.

These tests verify defined classes and the closed schema. They do not prove safety for every future schema change. Adding a free-text field requires a privacy review and failing canary tests before it can enter Share-Safe output.

## Before reporting a problem

Do not upload raw sysdiagnose, Console logs, crash reports, private exports, databases, pairing files, screenshots with private content, credentials, device identifiers, or precise locations. Use a Share-Safe packet you have inspected, or a small synthetic reproduction. GitHub issue warnings do not sanitize an attachment automatically.
