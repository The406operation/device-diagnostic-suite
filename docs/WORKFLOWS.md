# Capture workflows

Device Diagnostic Suite provides local macOS diagnostics for iPhone. Capture stays on the Mac. The app does not place calls, send messages, change phone settings, or upload evidence. See [Diagnostic sources](DIAGNOSTIC_SOURCES.md) for service limits and Developer Mode requirements.

## Baseline and paired comparison

1. Connect and unlock each phone. Accept a Trust prompt when needed. Install the external capture tools listed in [Build](BUILD.md).
2. Open **Paired Devices**. Select **Refresh phones**. Assign different phones to **Control** and **Primary**. The control is a baseline, not proof of cause.
3. Record the location, Wi-Fi state, cellular state, and other conditions. Keep both phones in approximately the same place and time window. Note differences in visible service and radio technology.
4. Select **Create matched session**. This records the conditions and links subsequent baseline runs. It does not run either baseline automatically.
5. Select **Run control baseline**, then **Run primary baseline**. Keep the selected phone connected. Each baseline records available metadata, a 45-second log sample, accessible diagnostics, and retained crash-report copies. A successful baseline also attempts a device log archive. Missing sources remain unavailable observations.
6. Review normalized fields, timed events, and capture errors. Record separately performed call or cellular page tests with action markers. The app's Mac HTTPS test does not measure the phone's cellular connection.

Repeat the same sequence and conditions for another matched session. Single-device **Live Logs** sessions and **Baseline/Comparison** good-service versus SOS sessions are separate from the paired campaign runs.

## SOS capture

1. Assign the primary phone. Open **SOS Watcher** and select **Arm watcher** before the fault occurs. Keep the Mac awake and the primary phone connected.
2. Check watcher freshness and connection state. The watcher retains rolling raw logs and periodic state queries. Candidate log triggers preserve an incident; a log trigger alone does not prove visible SOS.
3. Select **Mark SOS now** when SOS is visible. Record phone actions with timestamped markers. Marker time is the time of the app action; put any earlier action time in the note.
4. Select **Mark service restored** when service is visible. The watcher retains a recovery tail. Do not assume that visible service proves voice or data recovery.
5. Select **Stop watcher** to stop capture and disable automatic resume. Preserve the raw incident. Use **Attach to latest Primary run** to include the incident in that run's private export.

Arming enables watcher resume for the selected primary on later app launches. A fresh installation does not arm a watcher automatically. See [Architecture](ARCHITECTURE.md) for local storage and [Limits](LIMITATIONS.md) for interpretation.

## Sysdiagnose and log import

A paired run offers **Collect sysdiagnose**, **Collect log archive**, and **Attach raw evidence**. Collection depends on the connected phone, Xcode, and available services. Record failed requests as missing evidence. When needed, use the linked [Apple capture procedure](DIAGNOSTIC_SOURCES.md), record the trigger time and visible phone state, and retain the original archive.

The **Sysdiagnose Import** section accepts a text log, extracted folder, sysdiagnose archive, or logarchive. It performs bounded inspection. It does not retain the full original archive in single-session history or perform complete specialist analysis. Attach the original to a campaign run with **Attach raw evidence** when private preservation is required. **Crash & Analytics** also imports supported text reports or copies accessible reports while keeping the phone originals.

## Private Diagnostic Export

Select a run's **Private Diagnostic Export** to save the retained run metadata and associated raw evidence locally. Attach watcher incidents and imported evidence to the run first. Single-session exports contain retained session data and cannot recover text removed earlier. Protect this export as private diagnostic data. See [Privacy](PRIVACY.md) for exact scope.

## Share-Safe Export

Select **Share-Safe Export** to save the approved normalized fields, generic roles, event types, timestamps, comparison results, and conservative assessment. This mode omits raw evidence, identifiers, paths, filenames, and free text. Review the exported packet before sharing. Timestamps and software versions can still permit correlation. Do not upload a private export, raw logs, or sysdiagnose to a public issue.

## Observation and fault inference

An observation records what a query, log, Mac test, or user report shows. An inference proposes an explanation from those observations. Review facts, inference, confidence, contradictory evidence, uncertainty, and the next discriminating test separately. Missing telemetry is not a healthy result. Neither a stable control nor recovery after an action proves hardware, Apple software, or carrier fault attribution. Approve any configuration-changing test separately before performing it.
