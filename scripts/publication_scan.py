#!/usr/bin/env python3
"""Fail-closed publication input scan. Findings never print matched private values."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

PUBLISHABLE_PATHS = ['.github/ISSUE_TEMPLATE/bug_report.yml', '.github/ISSUE_TEMPLATE/config.yml', '.github/ISSUE_TEMPLATE/feature_request.yml', '.github/workflows/verify.yml', '.gitignore', 'CONTRIBUTING.md', 'LICENSE', 'Package.swift', 'PythonTests/test_resources.py', 'README.md', 'SECURITY.md', 'Sources/DeviceDiagnosticSuite/Analysis.swift', 'Sources/DeviceDiagnosticSuite/App.swift', 'Sources/DeviceDiagnosticSuite/CampaignAnalysis.swift', 'Sources/DeviceDiagnosticSuite/CampaignModels.swift', 'Sources/DeviceDiagnosticSuite/CampaignStore.swift', 'Sources/DeviceDiagnosticSuite/CampaignView.swift', 'Sources/DeviceDiagnosticSuite/Command.swift', 'Sources/DeviceDiagnosticSuite/DiagnosticStore.swift', 'Sources/DeviceDiagnosticSuite/ExportPolicy.swift', 'Sources/DeviceDiagnosticSuite/Models.swift', 'Sources/DeviceDiagnosticSuite/Resources/parse_logarchive.py', 'Sources/DeviceDiagnosticSuite/Resources/run_baseline.py', 'Sources/DeviceDiagnosticSuite/Resources/watch_sos.py', 'Tests/DeviceDiagnosticSuiteTests/AnalysisTests.swift', 'Tests/DeviceDiagnosticSuiteTests/CampaignAnalysisTests.swift', 'Tests/DeviceDiagnosticSuiteTests/ExportPolicyTests.swift', 'Tests/DeviceDiagnosticSuiteTests/Fixtures/README.md', 'Tests/DeviceDiagnosticSuiteTests/Fixtures/comparison.json', 'Tests/DeviceDiagnosticSuiteTests/Fixtures/telephony.txt', 'Tests/DeviceDiagnosticSuiteTests/SyntheticFixtureTests.swift', 'VERSION', 'build-app.sh', 'docs/ARCHITECTURE.md', 'docs/BUILD.md', 'docs/DEPENDENCIES.md', 'docs/DIAGNOSTIC_SOURCES.md', 'docs/LIMITATIONS.md', 'docs/PRIVACY.md', 'docs/PROVENANCE.md', 'docs/RELEASE.md', 'docs/WORKFLOWS.md', 'docs/dependencies.json', 'scripts/publication_scan.py']
# Exact synthetic values or upstream public references, never a blanket test-file exemption.
EXCEPTIONS = {
    "Tests/DeviceDiagnosticSuiteTests/AnalysisTests.swift": {"+1 " + "415 555 0100", "415 555 0100"},
    "Tests/DeviceDiagnosticSuiteTests/ExportPolicyTests.swift": {"202 555 0107", "02:" + "00:" * 4 + "07", "192." + "0.2.7", "2001:" + "db8::7", "45.123456" + "," + "-110.123456"},
    ".github/workflows/verify.yml": {"11bd71901bbe5b1630ce" + "ea73d27597364c9af683"},
    "scripts/publication_scan.py": {"415 555 0100", "202 555 0107"}
}
RULES = {
    "host_path": r"/(?:Users|home)/[A-Za-z0-9_.-]+",
    "email": r"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}",
    "udid": r"\b[0-9A-F]{8}-[0-9A-F]{16}\b|\b[0-9A-F]{40}\b",
    "subscriber_identifier": r"\b[0-9]{15,32}\b",
    "phone": r"(?:\+1[-. ]?)?\b[0-9]{3}[-. ][0-9]{3}[-. ][0-9]{4}\b",
    "wifi_mac": r"\b(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\b",
    "ipv4": r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b",
    "ipv6_example": r"\b[0-9A-F]{1,4}:[0-9A-F]{1,4}::[0-9A-F:]+\b",
    "coordinates": r"-?[0-9]{1,3}\.[0-9]{4,},\s*-?[0-9]{1,3}\.[0-9]{4,}",
    "private_key_or_certificate": r"-----BEGIN (?:[A-Z ]*PRIVATE KEY|CERTIFICATE)-----",
    "credential_token": r"\b(?:ghp_|github_pat_|sk-|AKIA)[A-Z0-9_-]{12,}",
    "jwt": r"\beyJ[A-Z0-9_-]{12,}\.[A-Z0-9_-]{12,}\.[A-Z0-9_-]{12,}\b",
    "credential_assignment": r"(?:password|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*[\"'][A-Z0-9/+_=.-]{12,}[\"']"
}

def scan(root, denied=()):
    root = Path(root)
    findings = []
    actual = set()
    for p in sorted(root.rglob("*")):
        relative = str(p.relative_to(root))
        if ".git" in p.relative_to(root).parts: continue # checkout metadata is never a publication input
        if p.is_symlink(): findings.append({"file": relative, "rule": "symbolic_link"}); continue
        if not p.is_file(): continue
        actual.add(relative)
        if relative not in PUBLISHABLE_PATHS and relative != "PUBLICATION.json":
            findings.append({"file": relative, "rule": "unapproved_file"})
        try: text = p.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            findings.append({"file": relative, "rule": "binary_input"}); continue
        for rule, pattern in RULES.items():
            for match in re.finditer(pattern, text, re.I):
                if match.group(0) in EXCEPTIONS.get(relative, set()): continue
                findings.append({"file": relative, "rule": rule, "line": text.count("\n", 0, match.start()) + 1})
        for value in denied:
            if value and value.casefold() in text.casefold():
                findings.append({"file": relative, "rule": "known_private_value"})
    for missing in sorted(set(PUBLISHABLE_PATHS)-actual): findings.append({"file": missing, "rule": "missing_input"})
    manifest = root / "PUBLICATION.json"
    if manifest.is_file():
        try:
            entries = json.loads(manifest.read_text())["files"]
            if set(x["path"] for x in entries) != actual-{"PUBLICATION.json"}:
                findings.append({"file": "PUBLICATION.json", "rule": "manifest_file_set"})
            for entry in entries:
                p = root / entry["path"]
                if p.resolve().is_relative_to(root.resolve()) is False:
                    findings.append({"file": "PUBLICATION.json", "rule": "manifest_path"}); continue
                if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != entry["sha256"]:
                    findings.append({"file": entry["path"], "rule": "manifest_hash"})
        except (ValueError, KeyError, TypeError, OSError): findings.append({"file": "PUBLICATION.json", "rule": "invalid_manifest"})
    return {"status": "PASS" if not findings else "HOLD", "filesScanned": len(actual), "findings": findings,
            "scope": "Exact publication inputs; pattern scan, optional private-value scan, manifest verification. Not an exhaustive security audit."}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--deny-list", help="Local JSON list of known private values. Never publish this file.")
    args = parser.parse_args()
    denied = json.loads(Path(args.deny_list).read_text()) if args.deny_list else []
    result = scan(args.root, denied)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["status"] == "PASS" else 1)

if __name__ == "__main__": main()
