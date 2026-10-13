# Build 36: server setup and connection recovery

The server setup flow now finishes with ChatGPT sign-in and a clear action to create an assistant on that server. Both existing-server and DigitalOcean routes use the same final step. An interrupted installation retains its saved identity; a matching failed download can retry a corrected Home package without replacing the owner or an installed Home.

Saved connections distinguish unavailable Keychain access from a disconnected server. An explicit Unlock connection action recovers the existing credential off the main thread, retaining drafts and history. New assistant names and setup notices follow the selected interface language; imported-name collisions use a numeric suffix.

## Validation before publication

- TypeScript typecheck passed.
- 93 targeted runtime, packaging, installer, store and archive tests passed.
- 163 native tests in 24 suites passed on the release-numbered source.
- The existing full runtime run passed 356 tests; source changes since that run are documented UI recovery labels and the release number.
- The native QA app reconnected to the existing paid server and displayed its 16 assistants, Server Desk history and verified attachment. Earlier live file creation, reading, app relaunch and deliberate service interruption remain documented in the server-journey report.

Publication, signing, installation and Apple processing are tracked separately and are not yet asserted by this preparation note. Private receipts are under `.data/release/2026-10-13-36/`.

## Remaining acceptance

The provider console and 1Password CLI on Mac mini still require sign-in. Clean-OS cloud installation, the preserved failed Home 35 attempt and deletion of the paid QA VM remain open. The proposed portable dictation engine has not replaced Apple dictation. Physical-device, natural-speech and extended native memory checks retain the boundaries in the central acceptance queue.
