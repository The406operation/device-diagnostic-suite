# Source provenance and publication boundary

Version 0.3.0-rc.2 derives from the exact audited 0.3.0-rc.1 public candidate. The changes rename the public project, update its storage namespace, and add the missing workflow document. Capture commands, privacy schemas, synthetic fixture bytes, dependency selection, and diagnostic behavior remain the same.

The audited public source originally derives from a completed local development version, 0.2.2. Seventeen reusable source/build/test/documentation inputs were inspected. The source ancestor had no Git repository. Two prior source ZIP snapshots were inspected as bounded lineage evidence and were excluded from the candidate.

Development source included personal role labels and one actual device identifier in a unit test. The candidate replaces role labels with Primary/Control, removes the actual identifier, and writes synthetic fixtures with invented timestamps, versions, types, and privacy canaries. It does not transform a real capture into a fixture. Free-text export channels were replaced by a closed Share-Safe schema. Private mode retains associated raw evidence. Export reports and session CSV remain available.

No development Git metadata, diagnostic campaign, session store, source ZIP history, real report, raw log, sysdiagnose, crash/analytics data, screenshot, build output, or private preservation inventory was copied. No file from the diagnostic evidence storage is a publication input. Private source and evidence preservation was checked separately by content hash and file metadata.

The exact publication root is this candidate directory. Do not publish its surrounding workspace. `PUBLICATION.json` names every file except itself. Its hash and the deterministic ZIP hash are recorded in the release audit. The manifest is included in the ZIP. That ZIP is source only; the locally verified app output is not a proposed publication input.

This provenance review found no existing project license or vendored third-party implementation in the inspected source lineage. It does not establish ownership rights for the owner. MIT remains a proposal until the owner approves the grant. No repository, push, upload, or publication occurred during candidate preparation.
