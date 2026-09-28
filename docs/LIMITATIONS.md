# Limitations and fault isolation

## Three fault domains

| Domain | Evidence that can support investigation | What it cannot prove alone |
|---|---|---|
| Device hardware | Repeated phone-associated failure, verified modem disappearance/reset, independent hardware findings | A failed phone beside a stable control does not prove hardware failure |
| Apple iOS/modem firmware/carrier bundle | Version-associated recurrence, relevant firmware traces, repeatable state behavior | Equal versions do not establish equal runtime state; airplane recovery is not a software diagnosis |
| Carrier provisioning/network | Decoded registration rejection, line-associated behavior, concurrent same-area failures | A rejection field without known protocol/meaning is not a provisioning diagnosis |

Reports separate observed facts, inference, confidence, contrary evidence, uncertainty, and the next discriminating test. Event order is scoped to retained classified events after a normal serving-registration entry. IMS impairment can remain active across that entry. Log timestamp precision and buffering do not establish causal precision. Phone/Mac clock offset is not measured automatically.

A stable control is a baseline. Compare both phones at approximately the same time, location, Wi-Fi/cellular settings, and procedure. Different radio technology, cell selection, lines, and prior state can confound comparison. A matched session guides the procedure; it does not synchronize hardware or clocks.

## Safe test matrix

1. Matched data and ordinary call tests, with operator approval and timestamps.
2. Simultaneous symptom observation and both-device logs.
3. Separately approved recovery actions, with before/during/after capture.
4. A separately planned line/device crossover, to test phone association versus line association.

A line crossover changes eSIM/carrier state and can itself remove a fault. A phone-associated result still leaves hardware versus Apple software unresolved. An absent fault after a change is not proof of repair. No destructive or carrier-account operation is automated by this application.

## Capture limits

Mac sleep, a cable disconnect, lost trust, a locked-device service, unavailable tools, and process failure can create gaps. A disconnect is not a proven reboot. Candidate SOS phrases can be false positives; confirm the phone display. Silence is not healthy service. The watcher restarts an idle log stream after 90 seconds and reports freshness. Confirmed incidents can grow beyond the rolling-ring bound through continued 15-minute incident files.

The generic text importer limits directory files, individual file size, line count, and matched events. Archive text import reads a bounded selection of telephony-related members. Full unified-log and sysdiagnose specialist analysis may require a separate approved workflow. No symbolication, complete panic interpretation, current radio measurement, direct phone DNS benchmark, cellular-only call test, SMS delivery test, or controlled throughput benchmark is claimed as automatic.

Archive expansion is not given a hard total-byte limit by the logarchive parser. Use trusted, locally collected inputs and sufficient free space. This is a disclosed importer limitation, not an exclusion from security review.
