# OpenStrudel — builds 45 and 46 continuation

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

## Post-release acceptance, 16 October

- Continued on `codex/post-release-45-acceptance` from `ceb4771`; primary and
  other chats' working files remain untouched.
- Recovered voice request completed in Wai Core Team. The actual answer gives
  this week's priorities and links a real Notion page, independently fetched and
  checked. This closes the dropped 08:25 request.
- In the isolated two-member QA group, queued audio, an image, an ordinary
  video and a CSV all produced the correct concrete answers. Two audio messages
  sent while processing were both answered. These audio fixtures were uploaded
  files, not native microphone recordings; that distinction remains in acceptance.
- Measured the shipped Whisper on the same eight-second fixture: 52.86 s at
  2 CPUs, 35.30 s at 4 and 36.84 s at 6. Wolf now has 4 CPUs, retaining the 2 GiB
  memory limit. Configuration backup, idle check, exact-service restart and
  health/data checks passed. The repeated real Telegram request took 45 s,
  versus 64 s before tuning. Voice works, but its latency still merits work.
- Verified the bot and owner's membership before connecting `wai team`,
  `wai активности` and `AiGid планы`. Each has an isolated root conversation and
  contextual participation; no synthetic messages were sent to those groups.
  Online SQLite backup and integrity checks passed. Wolf now has eight chat
  bindings; employee profiles and existing messages were preserved.
- Mac maintenance reclaimed about 3.4 GiB of physical space from verified idle
  reproducible caches. Free space is 6.1 GiB; memory pressure is normal. Active
  builds, Codex history, user data and release archives were retained. An exact
  duplicate old app was also removed after comparison with the managed rollback
  copy; APFS sharing means this is not counted as additional reclaimed space.
- Located the old personal OpenClaw source host and read the live WAI News and
  Wai Connect definitions, editorial rules and delivery journals. Wai Connect's
  latest failure is Telegram 401 after successful candidate preparation. The
  new personal Home still rejects this Mac's SSH key. No legacy schedule has
  been disabled and no second bot poller has been started.
- Remote MCP sign-in: the shipped Codex successfully completed an isolated
  OAuth fixture using an `openstrudel://` callback, with Codex owning PKCE,
  state validation, token exchange and storage. Product integration and live
  Notion acceptance remain open; the fixture is not a real Notion grant.

## Current continuation: remote sign-in and real voice notes

- Candidate 46 adds remote MCP OAuth callback forwarding over the paired Home
  connection. Native Codex still owns discovery, PKCE, exchange and tokens;
  temporary overrides do not rewrite service configuration. Pending logins are
  bounded, tied to the owner client, canceled on dismissal and rejected after
  access is revoked. An aborted initial HTTP request also cancels its login.
- Runtime suite: 515 passed, 2 skipped, including the aborted-login and
  unmentioned native-voice regressions. Native suite: 323 tests
  in 32 suites passed. Web Computer Use verified dismiss/retry, cancel/retry,
  the real Codex token exchange with a synthetic provider, and connected state.
  Private screenshot: `.data/release-46/web-oauth-connected.jpg`.
- Native browser opening still needs acceptance: AuthenticationServices starts
  its session, but its consent/browser window has not appeared in the Mac QA
  installation. Manual browser opening reaches the provider; duplicate QA and
  installed app URL handlers make that fallback insufficient proof. Do not
  publish candidate 46 or claim a real Notion grant from the synthetic fixture.
  The same opening problem was reproduced with Notion's real HTTPS login,
  then canceled; no Notion permission grant was made. An unsuccessful anchor
  experiment was reverted rather than retained as a speculative workaround.
- The owner's native Telegram voice note at 15:48 was received and transcribed,
  but the isolated QA group retained the old explicit `mentions` rule. Both
  it and a plain-text reproduction were recorded as context only. Telegram
  privacy mode was not the cause: the bot receives all group messages.
- Changed only that QA group's rule to contextual replies after a consistent
  SQLite backup on Wolf. No service restart or global rules migration was
  needed. New groups already use contextual replies in build 45; existing
  explicit settings elsewhere remain intact.
- Real post-fix evidence: unmentioned text 1678994 received the correct answer
  `51` in 1678995, about 10 seconds later. The owner's next native voice note
  1678996 received `Привет` in 1678998, about 42 seconds later. The voice was
  recognized after about 36 seconds; speech latency remains open despite the
  successful delivery. These are real Telegram notes, not uploaded audio files.
- Whisper's timing output isolates the speech cost: on the eight-second QA
  fixture, two encoder runs take 33.06 of 35.47 seconds (language detection and
  transcription). Upstream's experimental audio-context setting reduced the
  same fixture to 24.46 seconds with identical text. This was an isolated
  benchmark, not a production change: broader language/quality checks are
  required before adopting it. The production recognizer remains unchanged.
- Latest resource snapshot: 7.8 GiB disk free, normal memory pressure (61%
  free). Other development sessions are active; no process or data was removed.
- Candidate work is pushed as draft PR #49. Build 45 remains the released
  version; native remote sign-in acceptance is still required before merging
  and releasing this candidate.
- Closed the isolated QA app and OAuth fixture, stopped only the temporary
  `openstrudel-qa45` container, and closed its browser tabs. Production app and
  Wolf Home remain running. Test data, evidence and release archives are kept.

## Connected bot can send to its chats

- The owner's 16:21 DM exposed a real missing capability: normal Telegram
  replies existed, but employees had no native cross-chat send tool. The bot
  incorrectly recommended installing another Telegram service.
- Added `list_telegram_chats` and `send_telegram_message` to the existing native
  employee tool set. The already connected bot sends owner-requested text,
  files and GIF animations. Destinations come from current bot memberships;
  paused/removed chats and revoked owner access are checked at call time.
- The existing durable Telegram outbox tracks these sends. Identical calls in
  one request cannot duplicate delivery, and uncertain or partial delivery is
  not reported as success. Only requested content is copied into the destination
  conversation; private source history is not forwarded. Files stay inside the
  requesting employee's permitted workspace.
- Existing Codex execution threads renew once because dynamic tools are accepted
  at thread creation. Original thread IDs, all messages, profiles and bindings
  remain stored. Ordinary group participants and schedules retain their audience.
- Runtime validation: 526 passed, 2 skipped; typecheck and diff whitespace checks
  pass. Real Telegram cross-chat acceptance and production rollout are next.
- Native OAuth diagnostics also tested Apple's SwiftUI authentication API with
  an active app/key window. The browser still did not appear. That rules out a
  simple foreground-window fix; the diagnostic UI has been removed from source.
  Native OAuth remains unverified. No speculative activation workaround shipped.
- The owner explicitly requested committing and pushing all current work to
  main. This supersedes keeping candidate changes in draft, but does not make
  the outstanding native OAuth and multi-host release acceptance complete.
- Resource check: 9.4 GiB free, normal memory pressure (39% free). No user data
  or active build caches removed.

## Main merge and live Telegram follow-up

- PR #49 merged into main at `f7a08fd`; its merged local and remote branch was
  removed. Other chats' branches/checkouts remain intact.
- Wolf received `46-f7a08fd` after a packaged Linux smoke test, idle check,
  timestamped backup, atomic source swap and exact-service restart. Integrity
  and all counts were preserved (9 employees, 18 conversations, 6,893 messages,
  9 schedules, 8 bot chats). Backup: `/root/openstrudel-upgrade-46-20261016T134532Z`.
  This is a Home deployment; Sparkle and TestFlight still publish build 45.
- The first real DM test (1679023 → 1679024) failed before sending anything:
  AccountEngines resumed a second cached thread ID from settings after the
  conversation's ID was cleared. Added a regression through AccountEngines,
  cleared both execution references, and preserved both sets of previous IDs
  in one migration transaction. Canonical messages remain untouched.
- Added explicit delivered/pending/partial/unknown/not_sent tool receipts.
  An unreadable output file now becomes not_sent instead of remaining forever
  pending in the outbox. Both failure paths have regression tests.
- The parallel migration task owns missing histories, imported files/schedules
  and eventual legacy shutdown. This task retains News/Connect, Telegram/OAuth
  and releases. Do not stop the old gateway here or race its imports.

## Verified native Telegram sending

- PR #50 merged into main at `bf816e7`. The complete runtime suite passes:
  528 tests passed, 2 skipped. Packaged Linux smoke passed against the built image.
- Wolf now runs `46-bf816e7`. Backup:
  `/root/openstrudel-upgrade-46-20261016T135940Z`. SQLite integrity and all counts
  passed after the atomic deployment: 9 employees, 18 conversations, 6,895
  messages, 9 schedules and 8 bot chats. Execution migration v5 is active and
  the owner's DM starts a fresh native thread with both Telegram tools.
- Real owner-DM to isolated-group text delivery passed: 1679027 → 1679028,
  with confirmation 1679029, about 10 seconds. Only the requested destination
  received the text; the durable outbox reports delivered.
- The first GIF attempt had an unacknowledged transport failure and did not
  appear in the test group. The bot accurately reported uncertainty and did
  not resend automatically. The exact cause was not retained by the old generic
  error handling; do not label this a diagnosed network fault.
- A controlled direct animation upload succeeded. A separate new owner request
  then passed through the normal bot tool end to end: 1679037 → group animation
  1679038 → confirmation 1679039. The outbox confirms delivery, and Telegram
  metadata identifies the actual animation. The owner's subsequent independent
  DM GIF request also received a real attachment (1679040 → 1679041/1679042).
- Sparkle/TestFlight remain at 45. Native remote-service browser acceptance is
  still open; the web OAuth fixture is running again for that investigation.
- A parallel migration task reports a requested client-only Mac setup. Preserve
  the Mini's unique data and jobs until their destination and acceptance are
  verified; do not stop its Home or modify another task's imports speculatively.

## Owner time zone and Mac service sign-in

- The 17:27 report was traced to a missing `owner.timezone` on Wolf. The
  previous fallback advertised the Linux server's UTC zone as the owner's.
  After an online SQLite backup at `/root/openstrudel-timezone-20261016T143331Z`,
  the existing settings API initialized `Europe/Moscow`. All 11 schedule rows
  were unchanged; no restart was needed. The bot had already corrected the
  recurring request and paused the erroneous one-off UTC schedule.
- Actual owner-DM verification 1679065 → 1679066 confirms Moscow and the next
  requested send on Sunday 18 October at 16:20. This was a read-only request;
  no test content was posted to colleagues or a new schedule created.
- Missing owner time zones now remain unknown instead of silently becoming
  server UTC. New schedules use the owner default; editing with no timezone
  preserves the schedule's existing zone. Explicit UTC or another city still
  works. Tool receipts include the next run in local time. Native initialization
  retries on the next normal load after a failed save without losing owner access.
- Focused runtime tests: 27 passed. Native browser/account tests: 38 passed.
  The first full runtime run overlapped native compilation and hit timing limits
  in four unrelated files. With two workers and no concurrent compilation, all
  530 runtime tests passed (2 skipped); typecheck also passed.
- On Mac, service sign-in now opens the default browser and awaits the existing
  owner-bound callback. Codex still owns state/PKCE/exchange. iOS retains
  AuthenticationServices. Actual browser opening passed; full callback acceptance
  awaits an installed candidate because the production URL handler receives the
  isolated QA app's callback. Do not claim a real Notion grant or public release 46.

## Installed build 46 acceptance

- PR #51 merged at `36c2cb7`. PR #52's scoped notification hook is also included
  in the staged runtime from `c8a7d0f`; its focused notification/timezone checks
  passed (9 tests). Only the release version and generated Xcode project changed
  after the native acceptance tests recorded above.
- Mac 46 and its DMG are Developer ID signed, notarized (Accepted), stapled and
  accepted by Gatekeeper. Packaged runtime/installer checks: 5 passed. The app
  was installed atomically on this Mini after the managed backup
  `backup-20261016T144722Z-a66328f0`. Health and integrity passed; all 8 employee
  profiles, 18 conversations, 2,155 messages and 4 schedules remain. The app
  opens the original histories. The backup is marked healthy.
- iOS 46 archived and exported with the existing App Store signing identity.
  Apple accepted the upload, delivery `81339fbd-d34e-48ea-b7ef-94c5b1e2ae3a`.
  It is now VALID and IN_BETA_TESTING in the existing internal group Mik. Archive
  builds used the managed native wrapper; export used Xcode's separate export
  operation because it rejects the wrapper's DerivedData/project flags.
- Full installed-app service sign-in is still pending. The browser security
  policy blocked the test invitation's custom-scheme navigation and explicitly
  prohibits a workaround. The user has been asked to open that disposable local
  invitation manually. No real service permissions or production credentials
  were changed. Sparkle remains on 45 until this acceptance is complete.
- The parallel migration task reports both Wolf and WaiClaw on `c8a7d0f` with
  health/integrity/counts preserved and timestamped rollback snapshots. That
  task owns WAI Web hooks and MacBook client-only setup. Mini client-only awaits
  verification of its unique jobs and an actual remote connection.
- WAI News/Connect remain active in the old OpenClaw SQLite scheduler. Connect
  still fails Telegram authentication (401); the five active news/connect jobs
  and their source/delivery journals have not been disabled. The new personal
  host rejects this Mac's and the old host's existing SSH keys. Host-key checks
  remained strict; no credentials or access rules were changed.
- Safe cache cleanup removed 1.49 GiB of an unused reproducible dependency
  cache after an open-file check. Managed healthy-backup retention removed one
  older snapshot. Active builds, private data, release archives and Codex history
  remain intact; the current memory pressure is normal.
- PR #53 merged at `f0c4b5c`; its finished local/remote branch was removed after
  verifying both tips are ancestors of main. The main checkout is up to date.
  The final Home 46 archive passes both shipped extractors with matching source
  bytes; its packaging/installer suite passed 49 tests. Sparkle 46's archive
  signature and enclosure length also verify, but the public feed is still 45.
- Computer Use confirms the installed About panel shows 1.0 (46). Private proof:
  `.data/release-46/installed-build46.png`. Latest resource check: 8.3 GiB free
  disk space and normal memory pressure (55% free).

## News and Connect continuation

- Read the current legacy SQLite cron definitions, live editorial briefs,
  delivery journals and actual Telegram history. The latest confirmed News
  and Connect editions are dated 15 October. Connect's 16 October selection
  succeeded, but delivery returned Telegram 401; its three prepared cards
  were not committed to the delivery journal.
- Preserved a private, checksummed source snapshot in
  `.data/migration-news-connect`. No bot token is included. The old collectors
  and five active jobs remain enabled until the destination has passed real
  acceptance. The new personal Home still rejects this Mini's existing SSH
  credential; no access rules or credentials were changed.
- Fixed a migration prerequisite in the native scheduler: a saved Telegram
  destination now accompanies the run as trusted metadata. Separate-card
  requests can use the existing native send tool and durable receipts for
  exactly that destination. App-only runs cannot send to a bound Telegram
  chat. Ordinary participants keep their existing audience restrictions.
- The runtime suite passes: 538 tests passed, 2 skipped, plus typecheck.
  New integration coverage verifies two cards without an extra automatic
  post, duplicate-call coalescing, app-only isolation, and paused destinations.
  This change is newer than the staged Mac/iOS 46 artifacts; those artifacts
  have not been silently replaced or advertised as including it.
- PR #54 merged at `33aa98c`. Native Telegram sending also supports requested
  quiet delivery and link previews, so news need no legacy outbound bot token.
  Those options use the same durable outbox; changing presentation cannot
  duplicate the same content in one turn. The tool catalog renews once with
  prior execution IDs and account routes retained. All chat messages remain.
- Validation after delivery options: 542 runtime tests passed, 2 skipped;
  typecheck passed. The unchanged legacy news pipeline passes 137 tests.
  Two private Codex skill packages preserve News/Connect editorial rules and
  native delivery receipts. Connect's portable helper fixes UTC-day counting
  at Moscow midnight and rejects a nonnumeric delivery ID; 4 port tests pass.
  Both skill manifests validate. These packages are prepared, not deployed.
