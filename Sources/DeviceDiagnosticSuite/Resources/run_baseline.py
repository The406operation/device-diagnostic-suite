#!/usr/bin/env python3
"""Read-only, device-scoped baseline capture for the diagnostic campaign."""
import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import time
import uuid


ROOT = pathlib.Path.home() / "Library/Application Support/Device Diagnostic Suite Public/Campaign"


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def run(command, output, timeout=30):
    try:
        completed = subprocess.run(command, capture_output=True, timeout=timeout)
        output.write_bytes(completed.stdout)
        if completed.stderr:
            output.with_suffix(output.suffix + ".stderr.txt").write_bytes(completed.stderr)
        return completed.returncode
    except subprocess.TimeoutExpired as error:
        output.write_bytes(error.stdout or b"")
        output.with_suffix(output.suffix + ".stderr.txt").write_text("Timed out after %s seconds\n" % timeout)
        return -2


def observation(field, value, source, basis="Device query", note=""):
    return {"id": str(uuid.uuid4()), "field": field, "value": str(value), "basis": basis,
            "source": source, "observedAt": now(), "note": note}


def unavailable(field, reason):
    return observation(field, "Unavailable", "access audit", "Unavailable", reason)


def manifest(folder):
    rows = []
    for file in sorted(folder.rglob("*")):
        if not file.is_file() or (file.parent == folder and file.name in ("run.json", "manifest.json")):
            continue
        digest = hashlib.sha256()
        with file.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        rows.append({"id": str(uuid.uuid4()), "relativePath": str(file.relative_to(folder)),
                     "sha256": digest.hexdigest(), "bytes": file.stat().st_size,
                     "capturedAt": now(), "source": "read-only device capture"})
    return rows


def main():
    os.umask(0o077)
    os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + os.environ.get("PATH", "")
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--role", choices=("control", "primary"), required=True)
    parser.add_argument("--duration", type=int, default=45)
    parser.add_argument("--location", default="Not recorded")
    parser.add_argument("--wifi", default="Not recorded")
    parser.add_argument("--cellular", default="Not recorded")
    args = parser.parse_args()
    ids = subprocess.check_output(["idevice_id", "-l"], text=True).splitlines()
    if args.udid not in ids:
        raise SystemExit("Target phone is not connected or trusted")
    run_id = str(uuid.uuid4())
    folder = ROOT / "runs" / run_id
    raw = folder / "raw"
    raw.mkdir(parents=True, mode=0o700)
    os.chmod(folder, 0o700)
    os.chmod(raw, 0o700)
    record = {
        "id": run_id,
        "role": "Control" if args.role == "control" else "Primary",
        "deviceID": args.udid,
        "startedAt": now(), "endedAt": None,
        "timeZoneOffsetSeconds": int(dt.datetime.now().astimezone().utcoffset().total_seconds()),
        "context": {"location": args.location, "wifi": args.wifi,
                    "cellular": args.cellular, "testWindow": "45-second stationary log window",
                    "notes": "No phone settings were changed by this capture."},
        "observations": [], "events": [], "markers": [], "evidence": [],
        "status": "In progress", "errors": []
    }
    (folder / "run.json").write_text(json.dumps(record, indent=2))
    print("run_id=" + run_id, flush=True)
    print("stage=device metadata", flush=True)
    info = raw / "lockdown.plist"
    code = run(["ideviceinfo", "-u", args.udid, "-x"], info)
    if code != 0:
        record["errors"].append("Lockdown query failed: " + str(code))
        values = {}
    else:
        try:
            values = plistlib.loads(info.read_bytes())
        except Exception as error:
            values = {}
            record["errors"].append("Lockdown parse failed: " + str(error))
    names = {
        "model": "ProductType", "productType": "ProductType", "hardwareModel": "HardwareModel",
        "serialNumber": "SerialNumber", "deviceIdentifier": "UniqueDeviceID",
        "iOS": "ProductVersion", "build": "BuildVersion", "modemFirmware": "BasebandVersion",
        "simState": "SIMStatus", "esimEmbedded": "SIM1IsEmbedded",
    }
    for field, key in names.items():
        record["observations"].append(observation(field, values[key], "lockdown.plist") if key in values else unavailable(field, "The paired-device query did not return this field."))
    bundles = values.get("CarrierBundleInfoArray") or []
    bundle = bundles[0] if bundles else {}
    for field, key in (("carrierBundleID", "CFBundleIdentifier"), ("carrierBundleVersion", "CFBundleVersion")):
        record["observations"].append(observation(field, bundle[key], "lockdown.plist:CarrierBundleInfoArray") if key in bundle else unavailable(field, "Carrier bundle field not returned."))
    mcc, mnc = bundle.get("MCC"), bundle.get("MNC")
    record["observations"].append(observation("carrierMCCMNC", str(mcc) + "/" + str(mnc), "lockdown.plist:CarrierBundleInfoArray") if mcc and mnc else unavailable("carrierMCCMNC", "Carrier codes not returned."))
    for domain, key, field in (("com.apple.mobile.battery", "BatteryCurrentCapacity", "batteryPercent"),
                                ("com.apple.disk_usage", "AmountDataAvailable", "freeStorageBytes")):
        path = raw / (field + ".plist")
        code = run(["ideviceinfo", "-u", args.udid, "-q", domain, "-x"], path)
        try:
            response = plistlib.loads(path.read_bytes()) if code == 0 else {}
            value = response.get(key)
        except Exception:
            value = None
        record["observations"].append(observation(field, value, path.name) if value is not None else unavailable(field, "Domain query did not return this field."))
    detail = raw / "devicectl.json"
    code = run(["xcrun", "devicectl", "device", "info", "details", "--device", args.udid,
                "--json-output", str(detail)], raw / "devicectl-command.txt", timeout=20)
    if code != 0:
        record["errors"].append("Xcode device details incomplete: " + str(code))
    else:
        try:
            marketing = json.loads(detail.read_text()).get("result", {}).get("hardwareProperties", {}).get("marketingName")
            if marketing:
                record["observations"].append(observation("model", marketing, "devicectl.json:hardwareProperties"))
        except (OSError, ValueError):
            pass
    diagnostics = raw / "device-diagnostics.txt"
    code = run(["idevicediagnostics", "-u", args.udid, "diagnostics", "All"], diagnostics, timeout=30)
    if code != 0:
        record["errors"].append("Additional diagnostics unavailable: " + str(code))
    for field, reason in {
        "registrationState": "No direct registration query is available through the paired-device service.",
        "radioAccessTechnology": "No direct current RAT query is available through this Mac service.",
        "imsVoiceRegistration": "No direct IMS registration query is available through this Mac service.",
        "serviceState": "The paired-device service does not expose the status-bar service label.",
        "networkInterface": "The Mac cannot query the iPhone default data interface directly.",
        "dnsResult": "A Mac DNS test would measure the Mac, not the iPhone.",
        "connectivityResult": "A Mac HTTPS test would measure the Mac, not the iPhone.",
        "callResult": "No call was placed by the baseline routine.",
        "smsResult": "No SMS was sent by the baseline routine.",
        "cellularDataResult": "No iPhone data request was made by the baseline routine.",
        "rebootRecovery": "No reboot was performed.",
        "airplaneRecovery": "Airplane mode was not changed.",
        "signalBars": "The paired-device service does not expose status-bar bars.",
        "fieldTestSNR": "Field Test values require a user report from the iPhone.",
        "deviceLogArchive": "A log archive is collected separately because it can be large.",
        "archiveWindowLines": "A decoded log archive has not been attached to this run.",
        "sysdiagnose": "A sysdiagnose is collected separately to preserve the baseline window."
    }.items():
        record["observations"].append(unavailable(field, reason))
    print("stage=stationary logs", flush=True)
    log = raw / "device-syslog.log"
    err = raw / "device-syslog.stderr.txt"
    with log.open("wb") as output, err.open("wb") as errors:
        process = subprocess.Popen(["idevicesyslog", "-u", args.udid, "--no-colors", "-x",
                                    "-p", "CommCenter|CoreTelephony|basebandd|telephonyutilitiesd|callservicesd"],
                                   stdout=output, stderr=errors)
        time.sleep(max(5, min(args.duration, 120)))
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    print("stage=crash reports", flush=True)
    crashes = raw / "crash-reports"
    crashes.mkdir(mode=0o700)
    code = run(["idevicecrashreport", "-u", args.udid, "-k", str(crashes)], raw / "crash-copy-command.txt", timeout=150)
    if code != 0:
        record["errors"].append("Crash report copy incomplete: " + str(code))
    crash_count = sum(1 for p in crashes.rglob("*") if p.is_file())
    record["observations"].append(observation("crashReports", crash_count, "raw/crash-reports", note="Copy only; device originals retained."))
    record["evidence"] = manifest(folder)
    record["endedAt"] = now()
    record["status"] = "Complete" if not record["errors"] else "Complete with limits"
    (folder / "run.json").write_text(json.dumps(record, indent=2))
    (folder / "manifest.json").write_text(json.dumps(record["evidence"], indent=2))
    os.chmod(folder / "run.json", 0o600)
    os.chmod(folder / "manifest.json", 0o600)
    print("stage=complete", flush=True)
    print("folder=" + str(folder), flush=True)


if __name__ == "__main__":
    main()
