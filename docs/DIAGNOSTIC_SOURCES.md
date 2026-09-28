# Diagnostic sources

| Source | Measured or recorded | Limit |
|---|---|---|
| `idevice_id` | Connected USB device identifiers | Used locally for exact targeting; never shared in Share-Safe output |
| `ideviceinfo` | Reported product/build, modem version, SIM readiness, carrier-bundle fields, battery/storage | Missing keys and version compatibility remain possible; SIM ready is not registered service |
| `idevicepair validate` | Existing trust/pairing validity | No pairing records are copied or exported |
| `idevicediagnostics diagnostics All` | Accessible diagnostic response | Read-only query; not Apple’s protected hardware or modem diagnostics |
| `idevicesyslog` | Selected accessible telephony process logs and device log archive | Messages can be private, absent, stale, or buffered |
| `idevicecrashreport -k` | Accessible crash/analytics copies | `-k` retains phone originals; filename or process-list presence does not establish a crash |
| `xcrun devicectl` | Device details and optional sysdiagnose request | Xcode/iOS service support varies; some operations require Developer Mode or an unlocked device |
| macOS `log show` | Decoded local device logarchive | Five-minute review margin; line count is not a health metric |
| User-imported sysdiagnose | Selected text evidence and raw archive attachment | GUI text inspection is bounded; it is not full symbolication or complete archive analysis |
| Connected-device Console | Supported manual investigation alternative | The app does not control Console automatically |
| User markers and tests | Visible SOS/RAT, bars, Wi-Fi state, calls, SMS, page tests, recovery actions | Report time can differ from action time; phone tests are not automated by this suite |
| Mac HTTPS test | Mac HTTP result and elapsed time | It does not measure phone DNS, cellular data, voice, or registration |

Apple’s [crash and log acquisition documentation](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs) explains supported alternatives. [Profiles and Logs](https://developer.apple.com/feedback-assistant/profiles-and-logs/) lists additional Apple-supported capture sources. Profile installation requires an operator decision; this app does not install profiles.

Basic pairing queries and log services can work without Developer Mode. Developer Mode is relevant to Xcode developer services and companion installation. A failed Xcode sysdiagnose request is not a healthy result. Use the current [Apple on-phone sysdiagnose procedure](https://podcasters.apple.com/assets/iOS-sysdiagnose-logging-instructions.pdf) when appropriate, record the trigger and state, allow collection to finish, and attach the archive privately. Do not hold the button combination beyond Apple’s instructions. The app does not trigger the phone buttons.

Apple does not expose a complete live serving-cell, signal-strength, modem crash-counter, IMS, registration-cause, or status-bar interface to this Mac application. The app uses accessible services and logs. It requests no protected entitlement and performs no jailbreak or security bypass. A public CoreTelephony/Network companion could improve app-level network observations, but this release contains no companion.

Carrier bundle identifiers/codes are not the live serving-network identity. An unknown rejection protocol/code must remain uninterpreted. Raw signal values need verified units and validity. An app path failure does not by itself prove physical data-interface disappearance.
