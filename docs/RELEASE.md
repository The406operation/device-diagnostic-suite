# Release runbook

1. Start from reviewed reusable source. Use a new directory and a new public Git history. Do not copy private `.git` directories, source archives with private tests, evidence, derived data, exports, databases, screenshots, host paths, or metadata.
2. Use hand-authored synthetic fixtures. Never redact a real capture and then treat the result as a synthetic fixture.
3. Review changed fields in both export modes. Share-Safe must use the closed schema and pass canary tests. Private mode must retain useful associated evidence.
4. Run the publication scan on all intended files, not only tracked files. Investigate every hit. Fixture exceptions must be exact, synthetic, and bounded to a reviewed file/value.
5. Run Swift tests, Python parser/baseline/watcher tests, and a release app build from a clean temporary path. Record toolchain versions and failure limits. Do not connect to a real phone during release verification.
6. Review runtime linkage and dependency licenses. Do not add binaries silently. Owner approval of the project license is required before publication; adopt `LICENSE.proposed` as `LICENSE` only after that decision.
7. Produce `PUBLICATION.json` with exact paths and SHA-256 values. That manifest excludes itself by definition; the final audit/ZIP hash covers it. Build a deterministic source ZIP from only the listed files plus the manifest.
8. Scan the directory and a fresh ZIP extraction. Compare extracted files to the manifest. Reject extra files, metadata, links, private identifiers, and unknown publication inputs. Check private preservation separately.
9. Record PASS only for the verified source/privacy scope. Record HOLD for an exact technical or privacy blocker. Neither status grants publication authority or hardware-diagnosis confidence.
10. Stop. Repository creation, push, artifact upload, license adoption, remote CI execution, signing/notarization, and publication require separate authorization.
