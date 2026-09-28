"""Offline tests. All command results and device labels are synthetic."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources/DeviceDiagnosticSuite/Resources"

def load(name):
    spec = importlib.util.spec_from_file_location(name, RESOURCES / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class ResourceTests(unittest.TestCase):
    def test_same_parser_with_synthetic_telephony_fixture(self):
        module = load("parse_logarchive")
        fixture = ROOT / "Tests/DeviceDiagnosticSuiteTests/Fixtures/telephony.txt"
        start = module.utc("2031-02-03T12:00:00Z")
        events, latest, count, filtered = module.parse_lines(fixture.read_text().splitlines(), start, module.utc("2031-02-03T12:00:10Z"))
        self.assertEqual(len(events), 7)
        self.assertEqual(count, 4)
        self.assertEqual(events[1]["signal"], "Registration lost or emergency only")
        self.assertEqual(events[2]["signal"], "IMS or voice registration loss")
        self.assertEqual(latest["registrationState"][0], "kRegisteredHome")
        self.assertFalse(any(e["at"] == "2031-02-03T12:00:12.000Z" for e in events))
        # Review margin includes events outside the baseline, preserving the prior behavior.
        self.assertEqual(len(filtered), 8)

    def test_archive_traversal_and_links_are_rejected(self):
        module = load("parse_logarchive")
        for name, kind in [("../outside.txt", tarfile.REGTYPE), ("/outside.txt", tarfile.REGTYPE),
                           ("link", tarfile.SYMTYPE), ("hardlink", tarfile.LNKTYPE)]:
            memory = io.BytesIO()
            with tarfile.open(fileobj=memory, mode="w") as archive:
                entry = tarfile.TarInfo(name); entry.type = kind; entry.linkname = "outside"
                archive.addfile(entry)
            memory.seek(0)
            with tempfile.TemporaryDirectory() as temp, tarfile.open(fileobj=memory) as archive:
                with self.assertRaises(ValueError): module.safe_extract(archive, temp)

    def test_archive_regular_content_can_be_read(self):
        module = load("parse_logarchive")
        memory = io.BytesIO()
        content = b"SYNTHETIC"
        with tarfile.open(fileobj=memory, mode="w") as archive:
            entry = tarfile.TarInfo("nested/fixture.txt"); entry.size = len(content)
            archive.addfile(entry, io.BytesIO(content))
        memory.seek(0)
        with tempfile.TemporaryDirectory() as temp, tarfile.open(fileobj=memory) as archive:
            module.safe_extract(archive, temp)
            self.assertEqual((Path(temp) / "nested/fixture.txt").read_bytes(), content)

    def test_baseline_uses_scoped_read_only_commands_and_retains_manifest(self):
        module = load("run_baseline")
        commands = []
        class FakeProcess:
            def poll(self): return None
            def terminate(self): pass
            def wait(self, timeout=None): return 0
        def command(args, output, timeout=30):
            commands.append(args)
            if args[0] == "ideviceinfo":
                output.write_bytes(plistlib.dumps({"ProductType": "iPhone99,1", "ProductVersion": "99.1", "BuildVersion": "99Z999", "SIMStatus": "kCTSIMSupportSIMStatusReady"}))
            elif args[0] == "xcrun":
                output.write_bytes(b"synthetic command result")
                Path(args[args.index("--json-output") + 1]).write_text('{"result": {"hardwareProperties": {"marketingName": "Synthetic model"}}}')
            else: output.write_bytes(b"SYNTHETIC diagnostic result")
            return 0
        with tempfile.TemporaryDirectory() as temp, contextlib.redirect_stdout(io.StringIO()), \
             patch.object(module, "ROOT", Path(temp)), patch.object(module, "run", command), \
             patch.object(module.subprocess, "check_output", return_value="SYNTHETIC-DEVICE\n"), \
             patch.object(module.subprocess, "Popen", return_value=FakeProcess()), \
             patch.object(module.time, "sleep"), patch.object(sys, "argv", ["baseline", "--udid", "SYNTHETIC-DEVICE", "--role", "control"]):
            module.main()
            folder = next((Path(temp) / "runs").iterdir())
            run = json.loads((folder / "run.json").read_text())
            self.assertEqual(run["role"], "Control")
            self.assertEqual(run["status"], "Complete")
            for args in commands:
                if args[0].startswith("idevice"): self.assertEqual(args[args.index("-u") + 1], "SYNTHETIC-DEVICE")
                self.assertFalse(any(a in ("restart", "shutdown", "restore", "erase", "remove") for a in args))
            for entry in run["evidence"]:
                self.assertEqual(hashlib.sha256((folder / entry["relativePath"]).read_bytes()).hexdigest(), entry["sha256"])

    def test_watcher_freezes_synthetic_marker_and_stops_cleanly(self):
        module = load("watch_sos")
        class FakeProcess:
            def __init__(self, stream): self.stdout = stream; self.returncode = 0
            def poll(self): return None
            def terminate(self): pass
        with tempfile.TemporaryDirectory() as temp, tempfile.TemporaryFile() as stream:
            root = Path(temp); key = hashlib.sha256(b"SYNTHETIC-DEVICE").hexdigest()[:16]
            folder = root / key; commands = folder / "commands"; commands.mkdir(parents=True)
            (commands / "01-sos.json").write_text(json.dumps({"kind": "Observed SOS / No service", "at": "2031-02-03T12:00:00Z"}))
            (commands / "02-stop.json").write_text(json.dumps({"kind": "Stop watcher"}))
            with patch.object(module, "ROOT", root), patch.object(module, "connected_ids", return_value=["SYNTHETIC-DEVICE"]), \
                 patch.object(module, "value", return_value="Synthetic"), \
                 patch.object(module.subprocess, "Popen", return_value=FakeProcess(stream)), \
                 patch.object(module.select, "select", return_value=([], [], [])), \
                 patch.object(sys, "argv", ["watcher", "--udid", "SYNTHETIC-DEVICE"]):
                module.main()
            self.assertTrue(json.loads((folder / "status.json").read_text())["stopped"])
            incident = next((folder / "incidents").iterdir())
            metadata = json.loads((incident / "incident.json").read_text())
            self.assertEqual(metadata["status"], "Stopped before restoration; capture preserved")
            self.assertTrue((incident / "before").is_dir())
            self.assertTrue((incident / "manifest.json").is_file())

if __name__ == "__main__": unittest.main()
