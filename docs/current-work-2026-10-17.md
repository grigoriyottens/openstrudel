# OpenStrudel — build 47 acceptance

Continuation of `current-work-2026-10-16.md`; its completed checks are retained.
Work stays in the existing release checkout. The primary checkout and other
chats' changes are preserved. Intentionally deleted employees stay deleted.

## Verified

- Main is `16c5e71`; build 47 includes the employee setup correction in
  `9b18bb0` and the current Telegram runtime. The generated Xcode project now
  agrees with the already committed version 47 configuration.
- Wolf runs `openstrudel:9b18bb0`. The exact native remote-creation request that
  previously failed now saves the intended name and instructions. A subsequent
  request for `17 × 6 − 9` returned only `93` in the installed app. This uses
  the existing update_employee tool, without another model loop or setup state.
- Real remote Notion OAuth and the subsequent Conferences database read passed
  in the installed app, with the owner's explicit grant and no manual tunnel.
  The independent engine transcript confirms successful Notion tool calls.
- macOS 47 is built, bundled and Developer ID signed. Packaged runtime and
  installer checks pass (5 tests). The sequential cold vendor-binary checks
  now have a test-wide deadline consistent with their individual 10–20 second
  deadlines. The signed app is unchanged by this test-only correction.
- iOS 47 is archived and exported successfully with the existing release key.
- The two disposable employees created by this run were removed through the
  normal Home API after checking their exact IDs, test-only messages, no running
  work, no schedules, no files and no Telegram binding. Their rows were archived
  privately first; other employee IDs and database integrity were unchanged.
  The connected native sidebar removed both rows automatically and selected the
  root assistant, without manual refresh or restart.
- The native root history shows today's scheduled brief at 07:00 Moscow time.
  This is actual scheduled output, separate from the earlier synthetic checks.

## Release gates still open

1. Complete Apple notarization, verify the signed Sparkle feed and Home archive,
   publish immutable artifacts before switching public aliases, and verify the
   externally downloaded bytes with automatic rollback on failure.
2. Upload iOS 47 once, wait for VALID, and add it to the existing internal
   TestFlight group. Preserve the existing 46 release until this passes.
3. Verify the installed Mac update and actual remote data after relaunch.
4. Finish Mini's WaiClaw connection and client-only acceptance. Wolf is already
   connected. Preserve local archives and history until both remotes are usable;
   do not use the separately rejected disposable browser fixture.

## Resource check

On 17 October at 08:43 MSK, Mini had 11.66 GiB free on Data, normal kernel
memory pressure (level 1), and 3,053 MiB swap in use, down from 4,160 MiB at the
previous recorded check. The native build wrapper pruned one unlocked idle cache
(100.3 MiB). No application, server, simulator or other chat's build was stopped.
Disk space remains below the 15 GiB monitoring threshold; no additional verified
unused cache large enough to reach it was found. Current/shared build caches,
pending application update files, release archives, rollback copies, databases
and Codex history remain intact. Compact evidence is in the primary checkout's
private `.data/resource-monitor` directory.
