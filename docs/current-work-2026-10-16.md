# OpenStrudel — build 45 continuation

The owner's 16 October handoff is the baseline. Build 45 is now published from
`64fa34f` (PR #47, after the six earlier merged PRs). Do not repeat the completed
Wolf/WaiClaw cutover or restore intentionally deleted employees. The primary
checkout and other chats' files remain untouched.

## Plan and acceptance

1. Reconcile live Homes and the release queue. Preserve other checkouts and
   private state; work on `codex/release-45-acceptance` in the already attached
   `openstrudel-release33` checkout.
2. Make useful group participation and the owner's time zone normal product
   behaviour. Preserve explicit group settings and the audience of each chat.
3. Add device/employee reasoning choices only where the selected provider
   actually reports support. Use its native agent setting; no additional loop.
4. Fix stale Telegram approval controls across restarts. Recover the dropped
   voice request after reading its context, without replaying already completed
   work. Connect the three groups the owner named, retaining separate histories.
5. Verify app, web and Telegram with realistic text, image, file, audio/video,
   queue/steer, service, schedule, reconnect and delegation scenarios. Use an
   isolated chat for synthetic requests. Confirm actual results, not just health.
6. Review remote Notion sign-in, and migrate WAI News / Wai Connect from their
   old runtime without duplicate polling or schedule delivery.
7. Run runtime/native/packaged-app checks. Publish the signed, notarized Mac
   update, Home package and TestFlight build. Update documented Homes with
   backups, health/data checks and rollback on failure. Merge verified changes.
8. Record concrete evidence and remaining external limits; do not claim that
   all providers or every surface passed when only mocks were available.

## Resource maintenance

- A thread heartbeat `mac-mini` now checks disk and actual memory pressure
  every 12 hours. It is authorized to remove only verified unused reproducible
  caches, preserving active builds, user data, release archives and Codex history.
- Initial snapshot: about 9.3 GiB disk free; no memory pressure. Managed native
  cache pruning found no eligible cache. Other chats are actively building.
- This checkout's native builds must use `scripts/native-build.py` and its
  locked product snapshot, per AGENTS.md.

## Initial baseline (before this continuation)

- Fetched GitHub; `origin/main` is `1236b8f`. Primary checkout and its untracked
  files were left intact. The reused release checkout was clean before switching.
- Wolf's documented Home container is running. Its database has 9 employees,
  5 Telegram chat records and 9 schedules; these are a live baseline, not the
  earlier build-44 counts. No production changes have been made yet.
- Telegram confirms the voice failure and three historical approval cards from
  the handoff. The latest useful Notion and school replies are present.

## Build 45 changes and checks

- Provider-native reasoning is implemented for Home and employee selections,
  native app and web. Only reported levels are offered; unsupported saved choices
  are explained instead of silently changed. Codex delegates receive the selected
  effort; Claude uses its SDK catalog and ACP uses native configuration options.
- Owner time zone is initialized once by an owner client. New schedules and
  relative-date instructions use it; existing schedules retain their time zones.
- Newly connected groups use contextual participation. Explicit existing rules
  are retained. Telegram approval controls are tracked durably and stale controls
  are cleared without approving or replaying the action.
- Final runtime suite: 509 passed, 2 skipped. Native suite: 320 tests in 32 suites
  passed. A repeatable Swift 6.3.3 IRGen compiler crash in the approval picker was
  fixed by passing an explicit setter closure. Debug Mac build 45 succeeded.
- Computer Use verified the web model picker, save/reload, unsupported-level
  hiding, and English localization. Native QA connected an isolated Home, saved
  device Low, verified that the employee inherits Low, then saved employee High.
  These checks did not modify production model preferences.
- Recovered the original six-second voice message and transcribed it using the
  installed OpenRamble: “Волк, а что у нас на этой неделе в фокусе внимания?
  Распиши.” Recovery delivery still remains; no duplicate request has been sent.
- Resource check: normal memory pressure (54% free); about 6.8 GiB disk free.
  Removed only an unused reproducible Google Updater cache (~0.7 GiB). Active
  simulator/runtime/build files and the two managed rollback snapshots retained.

## Release and production acceptance

- Build 45 Mac app is signed, notarized (Accepted), stapled and accepted by
  Gatekeeper. Packaged-app checks: 5 passed. The DMG and Home package, stable
  aliases and signed Sparkle feed were verified through public HTTPS, including
  streamed artifact hashes. See [release evidence](releases/2026-10-16-build-45.md).
- TestFlight build 45 processed as VALID and is IN_BETA_TESTING in the existing
  internal group Mik. No external beta group was created.
- Wolf runs `openstrudel:45-64fa34f`. A quiesced, timestamped backup preceded
  the atomic source replacement and exact-service restart. SQLite integrity and
  employee/conversation/message/schedule counts were preserved; Telegram runs
  without errors. Rollback is retained on Wolf.
- This Mac runs the signed build 45. Its Home is healthy and the native app
  opens the existing employees and histories. All pre-upgrade row counts were
  preserved. The managed rollback snapshot is marked healthy, retaining two
  healthy snapshots. Installation used the staged signed app; an end-to-end
  Sparkle download/install was not repeated for 45.
- A fresh Linux container using the shipped 45 image passed TLS pairing,
  invitation consumption, remote employee creation, request idempotency,
  owner-time-zone initialization and persistence across a real restart.
  The AI engine in this isolated test was a mock; it is not live-provider proof.
- The three stale approval messages were already deleted in Telegram. Verified
  their lifecycle; no approvals or old work were replayed.
- The original 08:25 voice has now been recovered as a reply to the original
  message in Wai Core Team (MCP message 1678972). Awaiting and inspecting the
  actual answer; this is the owner's original request, not a synthetic test.

## Storage and remaining work

- Resource snapshot after rollout: 2.8 GiB free, normal memory pressure (59%
  free). Removed only verified unused reproducible caches; active builds,
  pending ChatGPT updater files, Codex history and user data were retained.
- The rollback snapshot encountered a live SQLite lock in the OpenStrudel
  office-search browser profile. The exact idle headless process was quiesced
  and restored after the backup. The helper now times out on a persistent lock
  and refuses to label the partial backup complete. Storage safety: 13 passed.
- Still open: live message-type/surface acceptance, the three named groups,
  WAI News/Wai Connect migration, remote Notion OAuth and remaining Homes.
  Grant and WaiClaw reject this Mac's existing SSH key. Do not reset credentials
  or report their deployments complete; investigate their documented access.
- Remote OAuth investigation confirmed native Codex callback configuration;
  no replacement authentication engine has been introduced.
- Private evidence/scripts are under `.data/release-45`; credentials, raw chat
  content and customer documents must not enter Git or public release assets.
