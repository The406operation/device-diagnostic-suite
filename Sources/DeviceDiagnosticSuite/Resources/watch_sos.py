#!/usr/bin/env python3
"""Bounded raw iPhone log ring with incident freeze on explicit SOS evidence or marker."""
import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import time
import uuid


ROOT = Path.home() / "Library/Application Support/Device Diagnostic Suite Public/Campaign/watcher"
SEGMENT_BYTES = 10 * 1024 * 1024
MAX_SEGMENTS = 20


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_json(path, value):
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2))
    os.replace(temp, path)


def append_json(path, value):
    with path.open("a") as stream:
        stream.write(json.dumps(value) + "\n")


def value(udid, key):
    try:
        command = subprocess.run(["ideviceinfo", "-u", udid, "-k", key],
                                 capture_output=True, text=True, timeout=5)
        return command.stdout.strip() if command.returncode == 0 else "Unavailable"
    except (subprocess.TimeoutExpired, OSError):
        return "Timeout"


def connected_ids():
    try:
        result = subprocess.run(["idevice_id", "-l"], capture_output=True, text=True, timeout=5)
        return result.stdout.splitlines() if result.returncode == 0 else []
    except (subprocess.TimeoutExpired, OSError):
        return []


def manifest(folder):
    files = []
    for file in sorted(folder.rglob("*")):
        if not file.is_file() or file.name == "manifest.json":
            continue
        digest = hashlib.sha256()
        with file.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        files.append({"path": str(file.relative_to(folder)), "sha256": digest.hexdigest(),
                      "bytes": file.stat().st_size})
    write_json(folder / "manifest.json", files)


def main():
    os.umask(0o077)
    os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + os.environ.get("PATH", "")
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    args = parser.parse_args()
    key = hashlib.sha256(args.udid.encode()).hexdigest()[:16]
    folder = ROOT / key
    rolling = folder / "rolling"
    commands = folder / "commands"
    incidents = folder / "incidents"
    for path in (folder, rolling, commands, incidents):
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = (folder / "watcher.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        lock.close()
        return
    segment_index = max([int(x.stem.split("-")[-1]) for x in rolling.glob("segment-*.log")] or [0]) + 1
    segment = rolling / ("segment-%06d.log" % segment_index)
    output = segment.open("ab")
    process = None
    partial = b""
    active = None
    incident_output = None
    last_state = 0.0
    last_status = 0.0
    last_log_at = None
    connected = False
    stopping = False
    last_stream_data = time.monotonic()

    def begin_incident(trigger, at, detail=""):
        nonlocal active, incident_output
        if active is not None:
            if trigger == "user marker":
                active["confirmed"] = True
                active["restored"] = None
            return
        incident_id = str(uuid.uuid4())
        target = incidents / incident_id
        before = target / "before"
        before.mkdir(parents=True, mode=0o700)
        output.flush()
        for file in sorted(rolling.glob("segment-*.log")):
            shutil.copy2(file, before / file.name)
        metadata = {"id": incident_id, "trigger": trigger, "at": at, "detail": detail,
                    "status": "Capturing during and after", "finishedAt": None}
        write_json(target / "incident.json", metadata)
        incident_output = (target / "during-after.log").open("ab")
        active = {"id": incident_id, "started": time.monotonic(), "restored": None, "target": target,
                  "confirmed": trigger in ("user marker", "continuation")}

    try:
        while not stopping:
            current = time.monotonic()
            if process is None or process.poll() is not None:
                if process is not None:
                    append_json(folder / "state.jsonl", {"at": now(), "event": "log stream stopped", "exit": process.returncode})
                    process = None
                ids = connected_ids()
                connected = args.udid in ids
                if connected:
                    errors = (folder / "watcher.stderr.log").open("ab")
                    process = subprocess.Popen(["idevicesyslog", "-u", args.udid, "-x", "--no-colors",
                                                "-p", "CommCenter|CoreTelephony|basebandd|telephonyutilitiesd|callservicesd"],
                                               stdout=subprocess.PIPE, stderr=errors)
                    os.set_blocking(process.stdout.fileno(), False)
                    last_stream_data = time.monotonic()
                    append_json(folder / "state.jsonl", {"at": now(), "event": "log stream started"})
                else:
                    time.sleep(2)
            if process is not None and process.stdout is not None:
                ready, _, _ = select.select([process.stdout], [], [], 1)
                if ready:
                    try:
                        chunk = os.read(process.stdout.fileno(), 65536)
                    except BlockingIOError:
                        chunk = b""
                    if chunk:
                        output.write(chunk)
                        output.flush()
                        if incident_output is not None:
                            incident_output.write(chunk)
                            incident_output.flush()
                        last_log_at = now()
                        last_stream_data = time.monotonic()
                        partial += chunk
                        lines = partial.split(b"\n")
                        partial = lines.pop()
                        for line in lines:
                            lower = line.lower()
                            service_transition = any(phrase in lower for phrase in
                                (b"service state: no service", b"service changed to no service",
                                 b"service state = no service", b"sos only",
                                 b"registration status: kemergencyonly"))
                            if service_transition and not any(phrase in lower for phrase in
                                (b"query", b"monitor", b"not in sos only")):
                                begin_incident("candidate service transition in log", now(),
                                               "Verify this log text against the visible iPhone state")
                        if output.tell() >= SEGMENT_BYTES:
                            output.close()
                            segment_index += 1
                            segment = rolling / ("segment-%06d.log" % segment_index)
                            output = segment.open("ab")
                            files = sorted(rolling.glob("segment-*.log"))
                            for old in files[:-MAX_SEGMENTS]:
                                old.unlink()
            if process is not None and time.monotonic() - last_stream_data >= 90:
                append_json(folder / "state.jsonl", {"at": now(), "event": "idle log stream restart",
                    "note": "No log bytes for 90 seconds; silence does not prove device health"})
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                process = None
                partial = b""
            for command in sorted(commands.glob("*.json")):
                try:
                    action = json.loads(command.read_text())
                    append_json(folder / "markers.jsonl", action)
                    if action.get("kind") == "Observed SOS / No service":
                        begin_incident("user marker", action.get("at", now()), action.get("note", ""))
                    if action.get("kind") == "Service restored" and active is not None:
                        active["restored"] = time.monotonic()
                    if action.get("kind") == "Stop watcher":
                        stopping = True
                finally:
                    command.unlink(missing_ok=True)
            if current - last_state >= 15:
                ids = connected_ids()
                connected = args.udid in ids
                append_json(folder / "state.jsonl", {"at": now(), "connected": connected,
                    "simStatus": value(args.udid, "SIMStatus") if connected else "Unavailable",
                    "basebandVersion": value(args.udid, "BasebandVersion") if connected else "Unavailable"})
                last_state = current
            if active is not None:
                elapsed = current - active["started"]
                restored_elapsed = current - active["restored"] if active["restored"] is not None else 0
                if (active["restored"] is None and elapsed >= 900) or (active["restored"] is not None and restored_elapsed >= 120):
                    target = active["target"]
                    previous_id = active["id"]
                    continue_capture = active["confirmed"] and active["restored"] is None
                    if incident_output is not None:
                        incident_output.close()
                        incident_output = None
                    metadata = json.loads((target / "incident.json").read_text())
                    metadata["finishedAt"] = now()
                    metadata["status"] = "Complete" if active["restored"] is not None else "No restoration marker within 15 minutes"
                    write_json(target / "incident.json", metadata)
                    for name in ("state.jsonl", "markers.jsonl"):
                        if (folder / name).exists():
                            shutil.copy2(folder / name, target / name)
                    manifest(target)
                    active = None
                    if continue_capture:
                        begin_incident("continuation", now(), "Ongoing confirmed SOS; continues incident " + previous_id)
            if current - last_status >= 5:
                write_json(folder / "status.json", {"pid": os.getpid(), "at": now(),
                    "connected": connected, "lastLogAt": last_log_at,
                    "segments": len(list(rolling.glob("segment-*.log"))),
                    "activeIncidentID": active["id"] if active else None,
                    "rollingBytes": sum(p.stat().st_size for p in rolling.glob("segment-*.log"))})
                last_status = current
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
        if incident_output is not None:
            incident_output.close()
        if active is not None:
            target = active["target"]
            metadata = json.loads((target / "incident.json").read_text())
            metadata["finishedAt"] = now()
            metadata["status"] = "Stopped before restoration; capture preserved"
            write_json(target / "incident.json", metadata)
            for name in ("state.jsonl", "markers.jsonl"):
                if (folder / name).exists():
                    shutil.copy2(folder / name, target / name)
            manifest(target)
        output.close()
        write_json(folder / "status.json", {"pid": os.getpid(), "at": now(), "stopped": True,
            "connected": connected, "lastLogAt": last_log_at})

        lock.close()


if __name__ == "__main__":
    main()
