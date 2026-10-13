# OpenStrudel: active work, 13 October 2026

User requests remain active when new questions arrive. Implementation and verification are separate; a build is not product acceptance.

| Request | Implementation | Verification |
| --- | --- | --- |
| Embedded Parakeet dictation: one optional download, automatic language recognition, no language picker or second application | Implemented checkpoint, not release-ready; commit `caf9b97` | Mac build and 7 focused tests pass; 1 optional audio test skipped. Actual Mac first download, cancel/retry and ready state checked. Pending: actual recognition, microphone-to-draft, offline inference, long recordings and iOS |
| Remove the top Conversations entry; keep employee navigation | Complete for the requested Mac sidebar; merged in PR #24 (`945ee2b`) | Actual Mac sidebar and switching employees checked. Included in source main, not yet in a new distributed app |
| Move an employee to another device from settings or by dragging to its sidebar section | Pending | Pending: two real runtimes, conversations/files/schedules, interrupted transfer, return trip; no duplicate execution |
| Paste a private SSH key as well as choose a file | Pending | Pending: valid and invalid key, password-protected key, actual setup UI |
| Investigate disappearing corporate ChatGPT connection | Investigating | Historical corporate identity is distinct from the personal identity. Exact deletion/replacement event not yet established; no claim of a cause |
| Simpler card checkout for server rental | Researching | Verify actual signup/checkout requirements and current WAI VDS readiness; do not label crypto-only or account-required hosting as card-only checkout |
| Regression checks and release | Pending | Check latest main and concurrent releases before merging/publishing; verify delivered app separately |

## Decisions

- Use Parakeet now, as explicitly requested. Do not add a second model or model selector for Hebrew. Hebrew interface remains supported; dictation does not support Hebrew.
- Ubuntu 24.04 LTS remains the supported automatic setup target. Ubuntu 26.04 exists; the installer currently rejects it. Changing this requires its own installation/recovery validation, not just copy changes.
- Preserve employees at the source until a verified transfer safely changes execution ownership. A failed network reply is not permission to delete data or activate two copies.
- Reuse the existing account identity (person plus workspace). Equal emails are not sufficient to consolidate corporate and personal connections.
- Keep credentials and private diagnostic data out of this document and Git.

## Mac mini continuation

The user requested a handoff on 13 October, before further implementation. The complete continuation prompt is [handoff-mac-mini-2026-10-13.md](handoff-mac-mini-2026-10-13.md). The checkpoint branch is `codex/employee-transfer-dictation`; only the completed sidebar change was merged to main. Do not treat the Parakeet checkpoint or the earlier Apple-recognizer acceptance as completed Parakeet validation.
