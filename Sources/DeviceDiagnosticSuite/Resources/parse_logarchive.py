#!/usr/bin/env python3
"""Decode a local iPhone log archive and extract conservative cellular event facts."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile
import uuid


def utc(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def iso(value):
    return value.astimezone(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def event(at, signal, summary):
    return {"id": str(uuid.uuid4()), "at": iso(at), "signal": signal,
            "summary": summary, "source": "telephony-logarchive-decoded.log"}


def observation(field, value, at, note):
    return {"id": str(uuid.uuid4()), "field": field, "value": value, "basis": "Device log",
            "source": "telephony-logarchive-decoded.log", "observedAt": iso(at), "note": note}


def safe_extract(archive, destination):
    members = archive.getmembers()
    if any(m.name.startswith("/") or ".." in PurePosixPath(m.name).parts or
           m.issym() or m.islnk() or not (m.isfile() or m.isdir()) for m in members):
        raise ValueError("Unsafe archive entry")
    archive.extractall(destination)


def parse_lines(lines, start, end):
    review_start = start - dt.timedelta(minutes=5)
    review_end = end + dt.timedelta(minutes=5)
    events = []
    observations = []
    latest = {}
    window_lines = 0
    filtered = []
    for line in lines:
        try:
            at = dt.datetime.strptime(line[:23], "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
        if not review_start <= at <= review_end:
            continue
        filtered.append(line)
        if start <= at <= end:
            window_lines += 1
        x = line.lower()
        if "registration status: kregisteredhome" in x:
            events.append(event(at, "Registered service", "Serving system registration: registered home"))
            latest["registrationState"] = ("kRegisteredHome", at)
        elif "registration status: kemergencyonly" in x:
            events.append(event(at, "Registration lost or emergency only", "Serving system registration: emergency only"))
            latest["registrationState"] = ("kEmergencyOnly", at)
        elif any(term in x for term in ("registration reject", "attach reject", "network reject", "5gmm reject")):
            events.append(event(at, "Registration rejection", "Explicit registration rejection text"))
        if "imsregistrationstate:" in x and "registered: knotregistered" in x:
            events.append(event(at, "IMS or voice registration loss", "IMS registration: not registered"))
            latest["imsVoiceRegistration"] = ("kNotRegistered", at)
        elif "imsregistrationstate:" in x and "registered: kregistered" in x:
            latest["imsVoiceRegistration"] = ("kRegistered", at)
        if "nepathevent cellular failed" in x:
            events.append(event(at, "Cellular data interface loss", "Cellular path failed for an app"))
            latest["cellularPathEvent"] = ("Failed cellular path for an app", at)
        if "kctregistrationradioaccesstechnology:" in x:
            rat = "5G NR" if "kctregistrationradioaccesstechnologynr" in x else \
                  "LTE" if "kctregistrationradioaccesstechnologylte" in x else None
            if rat: latest["radioAccessTechnology"] = (rat, at)
        if any(term in x for term in ("baseband reset detected", "baseband has reset", "modem reset detected", "baseband disappeared")):
            events.append(event(at, "Modem reset or disappearance", "Explicit modem reset or disappearance text"))
    return events, latest, window_lines, filtered


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-folder", required=True)
    args = parser.parse_args()
    folder = Path(args.run_folder)
    run = json.loads((folder / "run.json").read_text())
    archive_path = folder / "raw/device-logarchive.tar"
    if not archive_path.is_file():
        raise SystemExit("Device log archive is missing")
    start = utc(run["startedAt"])
    end = utc(run["endedAt"] or run["startedAt"])
    review_start = start - dt.timedelta(minutes=5)
    review_end = end + dt.timedelta(minutes=5)
    with tempfile.TemporaryDirectory(prefix="device-suite-logarchive-") as temp:
        extracted = Path(temp) / "device.logarchive"
        extracted.mkdir()
        with tarfile.open(archive_path) as archive:
            safe_extract(archive, extracted)
        output = folder / "raw/telephony-logarchive-decoded.log"
        errors = folder / "raw/telephony-logarchive-decoded.stderr.txt"
        command = ["/usr/bin/log", "show", "--style", "compact", "--timezone", "UTC", "--predicate",
                   'process == "CommCenter" OR process == "CoreTelephony" OR process == "basebandd"',
                   str(extracted)]
        with output.open("wb") as out, errors.open("wb") as err:
            code = subprocess.run(command, stdout=out, stderr=err, timeout=180).returncode
        if code != 0:
            raise SystemExit("macOS log decoder failed: " + str(code))
    events, latest, window_lines, filtered = parse_lines(output.read_text(errors="replace").splitlines(), start, end)
    output.write_text("# Device log timestamps are UTC; five-minute review margin\n" + "\n".join(filtered) + "\n")
    observations = []
    for field, (value, at) in latest.items():
        observations.append(observation(field, value, at,
            "Last matching log entry in the decoded review window. This is not a direct live device query."))
    observations.append(observation("archiveWindowLines", str(window_lines), end,
        "Decoded CommCenter/CoreTelephony/basebandd lines during this run. Line count is not a health metric."))
    observations.append(observation("deviceLogArchive", "Collected", end,
        "Raw archive is stored locally. The decoder used a five-minute margin around this run."))
    (folder / "raw/archive-events.json").write_text(json.dumps(events, indent=2))
    (folder / "raw/archive-observations.json").write_text(json.dumps(observations, indent=2))
    print("events", len(events), "window_lines", window_lines)
    print("last_registration", latest.get("registrationState", ("Unavailable",))[0])


if __name__ == "__main__":
    main()
