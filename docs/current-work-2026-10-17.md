# OpenStrudel — build 49 and Android 3, remaining device acceptance

## Latest checkpoint — 17 October, 19:54 UTC

Apple/Home source `de19fd0` is on main. Mac 49 and Home 49 are published;
versioned downloads, stable aliases, signed Sparkle feed and checksums were
independently downloaded and verified. iOS 49 is VALID and IN_BETA_TESTING in
the existing internal Mik group. Android 1.0 build 3 is publicly available and
installed on the USB Galaxy A07. Publication receipts are in `.data/release-49`
and `.data/android-release-3`. The isolated Sparkle 48 → 49 cycle passed actual
download, install, relaunch and the native up-to-date check. Installed bytes and
signature match the candidate. Production Home's PID and rows were unchanged;
the temporary QA feed was removed and the public production feed preserved.
The installed production application also reports up to date through Sparkle.
Android's final visual pass found raw Markdown in employee previews; the existing
renderer now produces plain preview text. Android-only `deff31b` is on main;
release compilation/lint and inspection of the actual phone passed. Its update
preserved the encrypted Mini connection. No Apple/Home rebuild was needed.

Wolf runs `openstrudel:de19fd0`; its eight Telegram chats, employee/history counts
and SQLite integrity are preserved. In the private two-member QA Telegram group,
without @mention, a real request returned 126 immediately in its answer and
saved a one-time reminder. The clock started 1 ms after its deadline; Telegram
delivered one reminder, also visible in the native Mac timeline. This is live
provider evidence, separate from the synthetic fixtures.

Mac mini now runs notarized build 49. Its Home was quiesced for a managed rollback
snapshot, then updated atomically. Health, integrity, data counts and the native
version/history passed. The temporary Android QA employee was then archived
privately and removed through the normal API; all other employee IDs stayed
unchanged. The connected phone no longer lists it.

Final regression: 586 runtime tests passed (two package-only tests skipped in
that invocation); all five checks against the signed package passed separately.
The 338 native tests plus the final two schedule tests passed. Android has twelve
unit tests, nine physical fixture tests and zero release-lint errors, with actual
provider requests and their limitations recorded in the Android acceptance note.

Rollback copying now uses standard independent APFS clones for ordinary files,
retaining the SQLite backup API and integrity checks. All fifteen storage safety
tests pass, including independent modification and unsupported-volume fallback.
The tooling-only change `f09fd0a` is also pushed to main; shipped application
artifacts remain built from `de19fd0`. Healthy-backup retention removed one old
managed snapshot after open-file checks. Data has about 5.6 GiB free, pressure is
normal and swap is declining. No other caches were eligible for deletion.

Still open: WaiClaw/CLO and Grant reject this Mini's existing SSH credentials;
their latest deployment/settings are unverified. Android's external route to
Wolf stalls independently in the platform HTTP client, so outside-network
acceptance remains open. No physical iPhone is available. Do not count Android
fixtures as physical iOS, actual QR decoding or new OAuth-install acceptance.
These limits remain part of the original goal; this is not full acceptance.

The entries below are chronological history; earlier pending-release statements
are superseded by this checkpoint.

## Android continuation — 17 October

The owner confirmed that no physical iPhone is available and requested a native
Android build and testing on the USB-connected phone. The Samsung Galaxy A07 is
authorized and available. Android-specific implementation and acceptance are
tracked in [the Android plan](android-acceptance-2026-10-17.md). This extends the
existing goal; it does not make Android evidence proof of iOS microphone or
Camera behavior. AiGid has released the heavy-build/audio queue.

Fresh SSH checks still reach WaiClaw and Grant but reject the documented root
credentials. No credentials were rotated and no access rules changed. Build 48
and the completed checks below remain valid; repeat only checks affected by new
code or new failures.

### Android acceptance checkpoint

The native Kotlin/Compose companion builds and is signed. Twelve unit tests,
eight physical-device fixture tests, release lint, real text/document/image
requests, editable ElevenLabs dictation and HTTPS App Links have passed on the
USB Galaxy A07. The detailed Android record separates fixtures, live provider
results and remaining limits. Android 1.0 build 1 (`f8d1246`) is published; the
public signed APK and manifest have matching SHA-256 checksums.

A shared Home issue was reproduced during the real reminder test: Codex used
`sleep`, its calculation was marked as commentary and omitted from the final
answer, and no schedule was persisted. Next runtime work must provide one-time
scheduling through the existing clock and return the calculation immediately.
The phone's external
Wolf route also still exhibits packet loss; local and USB paths are independent
positive results. WaiClaw/Grant SSH authentication and physical iPhone checks
remain open. Do not mark the whole product acceptance complete.

### Build 49 / Android 2 acceptance — 17 October, 14:40 UTC

One-time reminders now use the existing scheduler. The persisted string contract
also works with older Codex threads; no history rewrite, extra model loop or
schema migration. An exact deadline replaces the periodic timer only when it
is sooner, preserving the 15-second recovery check. Completed and uncertain
one-time results are shown separately from paused work in the native apps.

A real request sent from the Galaxy A07 returned its calculation, saved a
one-time reminder, survived a graceful restart of the isolated Home and delivered
once. A second real test after the deadline improvement started at 14:38:59.003
for 14:38:59.000 UTC; its model reply arrived about 19 seconds later. This proves
the clock deadline, not instantaneous provider response. The signed Android 2 UI
shows both completed receipts without an enable toggle. Evidence is retained in
`.data/release-49/android-live-reminders.json` and `android-one-time.png`.

Native macOS: 338 tests passed before the final skipped-status label. Runtime:
62 focused tests passed including deadline timing, restart, missed deadline,
uncertain delivery, explicit DST offsets and paused archive transfer. The initial
full suite had two timeouts during concurrent native compilation; their 13 tests
passed after that load ended, without increasing limits. Nine physical Android
fixture tests pass. Final serial regression and versioned releases are next.
Build 49 and Android 2 are not published yet.

## Current checkpoint — 17 October, 10:03 UTC

Build **48**, source `fb84d3d`, is published to Sparkle and the Home download.
Apple processed iOS 48 as VALID; it is IN_BETA_TESTING in the existing internal
Mik group. The notarized app is installed on Mini, and Wolf runs the same source.
See [build 48 acceptance](releases/2026-10-17-build-48.md) for evidence and limits.
The entries below this checkpoint are chronological history, including gates
that were subsequently closed; they are not the current release status.

Completed since the previous checkpoint:
- Native macOS 336 tests, runtime 573 tests, three iOS model UI scenarios and
  five signed-package checks passed. Both Home archive extractors passed.
- ElevenLabs is selected and connected on Mini and Wolf. Real native recognition
  produced editable text before send; real Telegram without a mention produced
  its transcript before the correct answer. Per-chat model selection was verified
  both in native/web fixtures and in a real Telegram/Codex turn.
- Signed/notarized macOS 48 was installed after a managed rollback snapshot;
  health, SQLite integrity, existing row counts and actual remote history passed.
  The successful snapshot was marked healthy; normal retention kept two backups.
- Public immutable downloads and stable aliases have matching hashes. One
  verification download was truncated by the network; the first rollback SSH
  attempt also lost its connection. Subsequent origin inspection, complete
  downloads from Mini and Wolf, and the installed Sparkle UI confirmed build 48.
- Closed only this task's QA apps and fixtures and shut down its simulator.
  AiGid has the current heavy-build/audio queue; do not start new native builds
  or disturb its simulator until that work releases the queue.
- Safely removed the idle, reproducible Sparkle extraction for build 48 after
  checking processes, open files and mounts. The signed DMG is retained. About
  966 MiB of free space was recovered; Data then had 5.84 GiB free. Native cache
  pruning found no eligible caches. Disk remains below the 15 GiB threshold.
- Removed 18 merged remote branches after checking their exact tips, ancestry,
  absence of open pull requests and absence from attached worktrees. Deletion
  was atomic and conditional on unchanged tips. Active worktree references and
  main were preserved; the private receipt retains every removed tip.
- Two historical GIF previews initially failed during the network interruption.
  Their stored files and authenticated API reads were intact; the native Retry
  action loaded both correctly. No attachment migration or speculative decoder
  patch was applied. Latest resource snapshot: 5.85 GiB free, normal pressure,
  6,037 MiB swap, down from the previous 6,117 MiB.
- The full native Sparkle cycle from 45 to 48 passed in separately identified,
  signed and notarized QA copies: discover, download, install, relaunch, and
  report up to date. Installed executable/dylib/plist bytes matched the candidate;
  signature verification passed. Production Home's PID, health, integrity and
  row counts were unchanged. The temporary HTTPS feed/archive were removed
  after checking their hashes; the production appcast hash remained unchanged.
- A fresh, isolated Home using the exact Wolf 48 image passed its real Codex
  filesystem sandbox check, first startup, unauthorized-request rejection,
  creation of two employees, restart persistence, Moscow timezone persistence,
  rename without losing instructions, and deletion of those test employees.
  It had no external network, published ports, model credentials or bot token.
  Its container and volume were removed; the production container was unchanged.
- Removed the idle extraction cache made by the Sparkle QA check after process,
  open-file and mount checks. It recovered another 46.9 MiB; Data then had
  6.74 GiB free. Signed archives and all user data remain preserved.
- Read-only completion audit through the personal Telegram MCP found today's
  WaiClaw deliveries in both News and Connect (06:03 and 06:01 UTC). The recovered
  Core Team voice request and its substantive answer with a Notion result remain
  present. This verifies delivery, not WaiClaw's currently installed build.
- Wolf currently reports a running bot without a connection error, all eight
  expected enabled chats, configured Europe/Moscow, connected ElevenLabs
  (Scribe v2 / Eleven v4), and a connected Pro Max account. Its live catalogue
  reports six models with provider-supported reasoning/speed options. Mini also
  reports Moscow and connected ElevenLabs; its separate local account reports
  Pro, not Pro Max. Mini's account and preserved local Home were not replaced
  during the pending client-only migration.
- The existing Mac mini resource heartbeat is ACTIVE with a 12-hour interval.
  No duplicate monitor was created. Current read-only audit receipts are under
  `.data/release-48/completion-audit`.

Still open, without restoring deleted employees or resetting credentials:
1. WaiClaw/WAI.co and Grant reject this Mini's documented SSH access. Their 48
   deployment, ElevenLabs defaults and requested account status are not verified.
   Mini's second real remote connection and final client-only migration depend
   on WaiClaw access; local data, Home and relay remain preserved.
2. The paired physical iPhone is currently unavailable to device tools.
   Actual microphone quality/latency,
   system Camera Universal Links and the reported two-add/two-remove incident
   need physical-device acceptance. Simulator coverage is recorded separately.
3. A full bootstrap on a newly provisioned Ubuntu server was not repeated for 48.
   Fresh Home startup/restart and the isolated Sparkle cycle now pass; the exact
   Home image, shipped installers, public signatures, installed app and remote
   production upgrade passed the checks listed in the release note.
4. Remaining device-specific live checks require those hosts or the iPhone.
   Keep synthetic-engine coverage separate from actual provider responses;
   neither today's deliveries nor the release receipt proves full acceptance
   on inaccessible devices.

The same host-authentication and physical-device blockers have been confirmed
across three consecutive goal turns. A fresh check still returns SSH permission
denied on WaiClaw and Grant, including the explicit existing local key, and
devicectl still reports the paired iPhone unavailable. No credential reset,
new access rule, competing publisher, or local-service shutdown was attempted.
Resume deployment and device acceptance when existing host access is restored
and a physical iPhone is available; do not rebuild or repeat completed tests
without a new change or failure.

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

1. Completed: both macOS notarizations accepted, app/DMG stapled and assessed.
   Sparkle 47 and Home 47 are public; immutable downloads, signed feed and stable
   aliases were independently downloaded and verified after atomic publication.
   Previous public pointers have a timestamped rollback copy. Evidence:
   `.data/release-47/published47.json` and `sparkle-verified47.json`.
2. Completed: iOS 47 uploaded once, processed VALID and added to the existing
   internal Mik TestFlight group, IN_BETA_TESTING. Delivery receipt and current
   Apple state are in `.data/release-47/ios`.
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

The local update backup stopped on the live Office browser's exclusively locked
`office-search/chrome-profile/first_party_sets.db`. Its incomplete snapshot is
retained for inspection and must not be marked healthy. The browser was not
stopped. Installed Mini remains 46 until a valid rollback snapshot is available.
Free space subsequently measured 7.6 GiB; no additional cleanup was performed.

## Build 48 — speech, in progress

User explicitly supplied the ElevenLabs credential location in 1Password and
requested the latest recognition/voice models plus transcript-first replies.
The key is read only in process memory. Do not put it into Git, logs or URLs.

Verified evidence:
- Personal Telegram MCP now works. Wai Reflections' historical messages show
  a separate `📝` transcript before its substantive reply. The actual failed
  135-second OGG (message 1679144) and successful 73-second OGG (1679025) were
  downloaded privately into `.data/voice-48`.
- Scribe v2 recognized those recordings in 3.21 and 2.55 seconds. This proves
  successful recognition, not perfect word accuracy. The integrated service
  subsequently passed real MP3/WAV/M4A/AIFF/OGG phrase checks; the long recording
  took 2.8 seconds. Eleven v4 returned a real playable MP3 in 2.63 seconds.
- Current official models documentation and the authenticated account catalog
  confirm `scribe_v2` for files and `eleven_v4` for speech generation.
  References: https://elevenlabs.io/docs/api-reference/speech-to-text/convert
  and https://elevenlabs.io/docs/overview/capabilities/text-to-speech/eleven-v4
- Native macOS compilation succeeded. Focused speech, voice, message, file and
  Telegram tests passed (54), then Home routing/credential tests passed (35).

Implementation under review:
- One Home speech setting: local or ElevenLabs; key is private, owner-managed,
  and relayed using existing ephemeral key transport rather than command logs.
- Telegram audio/video and audio sent as a document use the chosen recognizer;
  a durable transcript preview precedes the existing employee turn. Preview
  delivery stays inside the existing media FIFO. A preview network error does
  not drop the request. Context-only chats remain quiet.
- App/web audio attachments get a visible transcript notice before the answer.
  Original request identity stays unchanged so duplicate submission stays safe.
- Native dictation keeps editable text, explicit send and recoverable recordings;
  settings/setup offer ElevenLabs without requiring a local model download.
- Optional `generate_speech` uses the existing employee tools, file attachments
  and Telegram outbox; generated MP3 uses Telegram's audio player.

Remaining for 48: extended Telegram and native draft tests, translations and
privacy wording, video/live app/web/Telegram acceptance, full relevant suite,
review, commit/push, versioned release. Personal WaiClaw deployment still needs
working access; do not claim its timeout fixed merely from an API fixture.
Keep signed/public 47 artifacts unchanged.

## Added 17 October — connection stability and entry points

The user's latest report supplements speech work: two connections were added and
another two removed on iPhone, but the list later reverted; QR scanning is not
consistently discoverable; invitations from the system Camera fail; desktop
sharing and connecting are confused. Check both device persistence and service
settings rather than assuming the ambiguous spoken “connectors” means one only.

Acceptance work, in order:
1. Reproduce two-add/two-remove across refresh, background and relaunch. Inspect
   old in-flight responses and saved credentials. Preserve unrelated connections.
2. One receiving flow on iPhone, from initial setup, plus, and Settings: scan QR
   or paste a link, then review the destination and connect.
3. Clearly distinguish adding another Mac/server from sharing this device's
   employees. One sharing action with an explicit own-device/colleague role.
4. A camera-readable HTTPS invitation with native Universal Link handling,
   strict parsing, and a browser fallback. Keep invitation credentials in the
   URL fragment, outside HTTP requests/access logs. Preserve legacy links.
5. Capture and verify light/dark, compact iPhone, large text and Mac layouts,
   cancellations, malformed/expired links, connection loss and repeat opening.
6. Complete speech 48 acceptance, full relevant checks and review before shipping
   the combined verified release. A real iPhone is currently unavailable to
   devicectl; simulator checks must not be described as physical-phone acceptance.

Evidence captured before editing: `.data/connections-48/mac-devices-before.png`
and `mac-connect-before.png`. The current Mac sheet duplicates its title and
emphasizes removal above sharing. Native source already offers the same scanner
in the additional-connection view; verify the installed iOS build/state rather
than claiming that the user's intermittent missing scanner is already fixed.

Research: Apple Universal Links / TN3155, official Dots getting-started, and Grok
Bot overview/get-started. Adopt continuity of work, visible connection state and
short task-oriented entry points; do not add a parallel agent harness.
https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app
https://developer.apple.com/documentation/technotes/tn3155-debugging-universal-links
https://help.openai.com/en/articles/20001530-getting-started-with-your-dot
https://docs.x.ai/grok-bot/get-started

## Added 17 October — phone dictation and per-chat models

The user confirms these requests are additive, not replacements:
- Configure ElevenLabs as the default recognizer on every owned, documented
  Home (including WAI.co and WolfWolf), using the supplied 1Password key. Keep
  the local choice available. Measure real phone/native upload-to-text latency
  and accuracy; do not equate an API call with actual microphone acceptance.
- Add a compact model/speed choice in each conversation. Employee defaults stay
  unchanged unless explicitly edited. Reuse the engine catalog and supported
  tiers/reasoning; show Fast/Ultra Fast only when that model/provider supports it.
- Inspect authorized account identities and plans on WAI.co and WolfWolf. The
  user expects the previously authorized 500-tier subscription on both; its
  presence is unverified. Do not infer identity from email alone or print tokens.

Connection changes now pass 28 focused native tests and 16 invitation/runtime
checks. Two-add/two-remove survives reconstruction, and removal is saved before
slow remote logout. This reproduces a vulnerable persistence window, not yet
proof that it caused the reported phone incident. The simulator parses the HTTPS
invitation and presents the destination before redemption; the large-text screen
keeps the scanner and field reachable. One UI test failed only at its localized
Cancel selector; it is being corrected. Mac sharing choice and QR sheet inspected
in an isolated Home. Physical Camera/Universal Link acceptance remains open.

## 17 October checkpoint — public links and native acceptance

- Published the HTTPS invitation page and AASA declaration on the existing
  waiwai.is origin and static edge. Existing app associations were preserved.
  Both public responses were downloaded and byte-verified. Deployment backup:
  `/var/backups/openstrudel-invitations/20261017T065719Z` on the origin.
  Evidence is private under `.data/connections-48`.
- Enabled the iOS Associated Domains capability. Apple invalidated the old
  provisioning profiles when the capability changed; a new App Store profile
  uses the existing signing certificate. Development profile refresh remains.
- Both isolated iOS UI scenarios passed, including normal and largest text,
  HTTPS invitation review, scan/link entry points and cancellation. This is
  simulator acceptance, not physical Camera/microphone acceptance. Mac v2
  compilation also passed.
- Full runtime run: 562 passed, two skipped, one outdated transcript expectation.
  Updated that expectation for transcript-before-answer; the affected context
  and speech suites now pass all 20 tests, and TypeScript checking passes.
- AiGid has the user's priority for heavy Mini checks. OpenStrudel's completed
  acceptance simulator AE104B52-E8FF-4756-AF20-B68EA4564410 is shut down. No new
  native builds or microphone configuration changes until that queue is released.
  Code work, remote deployment preparation and lightweight checks continue.
- Per-chat models will reuse the existing catalog, account engine and model
  setting UI. Official speed documentation confirms that Fast/Ultra Fast
  availability depends on model and account, not an assumed plan label:
  https://learn.chatgpt.com/docs/agent-configuration/speed

Additional speech evidence: a real MP4 passed through the new Home transcription
API in 0.59 seconds, and an M4A upload produced its visible transcript before a
synthetic employee answer. This proves the media/API ordering, not live model
answer quality. Results: `.data/voice-48/live-api-result.json`.
Mac v2 devices and sharing layouts were inspected; a small subsequent correction
hides the local-model section immediately when ElevenLabs is selected.
New Development profile `OpenStrudel Development Links 20261017` is ACTIVE and
uses the same existing certificate and device roster. The Xcode project was
regenerated without starting a build.

## 17 October checkpoint — speech live on Wolf

- Commit `c8297d6` is on main. Wolf now runs that image with the existing
  company/personality/history intact. Deployment waited for idle queues, kept
  a consistent backup, replaced the source atomically, and verified health,
  Telegram, SQLite integrity and unchanged-or-increased row counts. Private
  backup: `/root/openstrudel-upgrade-48-20261017T071501Z`.
- ElevenLabs is the selected recognizer on Wolf. The key came from the named
  1Password item through process memory and stdin; no key is in Git or logs.
  Home API M4A recognition took 0.65 seconds.
- Real Telegram acceptance, isolated two-member QA group, without @mention:
  voice message 1679171 at 07:19:30 UTC, transcript 1679172 one second later,
  correct live employee answer 1679173 at 07:19:41. The answer was “Все коробки
  стоят 600 рублей.” No test was sent to a group containing colleagues.
  Receipt: `.data/voice-48/telegram-live-acceptance.json`.
- Wolf's first account is authorized and its current credential reports
  `promax`; Codex's older account display reported `unknown`. The display-only
  fallback checks account identity and credential expiry. Model capabilities
  still come from Codex. Do not infer subscription price from the label alone.
- WaiClaw/WAI.co still rejects the documented SSH access. Its deployment,
  speech default and requested account have not been verified. No credentials
  were rotated.

## Per-conversation models — acceptance in progress

- The existing model selection now supports conversation → employee → device
  inheritance. Model, speed and reasoning remain one validated provider choice.
  The same setting reaches queued turns, Telegram, services, remote Homes,
  archive transfer and provider removal. Running work keeps its existing choice.
- The conversation envelope carries its effective choice, so clients do not
  fetch the model catalog on every transcript poll. Account status follows the
  chosen conversation provider. Native stale-account rejection also checks the
  effective model, not only the selected employee.
- Web UI acceptance passed actual clicks: Sol/Ultra Fast/High, saved across
  reload, another employee unchanged, Luna hides unsupported controls, unsaved
  choice cancels, inheritance restores, catalog failure recovers with Retry.
  A 390×844 viewport fits the settings without horizontal overflow. Evidence:
  `.data/voice-48/chat-model-web-phone.png`. This fixture uses real HTTP and
  storage but a synthetic model; it is not live model latency evidence.
- 91 focused runtime tests passed, then 33 account/provider/localization checks
  and 14 model checks including old-schema upgrade, reopen and group capability
  filtering passed. TypeScript checking passes. Full serial runtime suite
  passed: 572 tests, two packaged-app checks skipped without a signed app path
  (75 suites passed, one skipped; 126 seconds).
- Native composer/settings and account-scope tests are implemented but await
  compilation and UI acceptance after AiGid explicitly releases the heavy-test
  queue. Do not publish these as accepted yet.
- At the last check memory pressure was normal; Data had about 7 GiB free.
  No new native builds, memory-routing changes or speculative cache deletion.

Next: finish runtime review/commit/deploy, native compilation and UI acceptance
when the shared queue permits, then signed versioned 48 Sparkle/Home/TestFlight.
Mini installation still needs a valid managed rollback snapshot; physical
iPhone Camera/microphone acceptance and inaccessible Homes remain separate gates.

Both finished native QA48 app processes were closed through their normal Quit
action and verified absent. Production OpenStrudel and AiGid were untouched.

## 17 October, 07:56 UTC — live conversation model acceptance

- Main `ba4f1ad` is pushed. Wolf now runs its image after an isolated real-image
  smoke, idle queue check, consistent backup, atomic source replacement and
  exact-container restart. Health, Telegram, SQLite integrity and data counts
  passed. Backup: `/root/openstrudel-upgrade-48-20261017T074933Z`.
- Only the two-member QA chat temporarily selected GPT-6 Sol / Fast. A real
  Telegram request without @mention (1679183) received the correct answer `215`
  (1679184) six seconds later. The chat then returned to employee inheritance,
  effective Astra / Ultra Fast, and the employee defaults were unchanged.
  Receipt: `.data/voice-48/wolf-chat-model-live.json`.
- ElevenLabs remains selected and connected after deployment. The live account
  API now reports the authorized Pro Max plan. Model and speed availability
  still comes from the actual Codex catalog, separately from the plan label.
- Mini observation: 6.88 GiB free, normal memory pressure, 5,905 MiB swap used
  (down from 7,089 MiB). No cleanup or new native build was started. AiGid still
  owns the heavy-build and audio queue; native model acceptance is pending.


## 17 October, native acceptance resumed

- AiGid released the Mini build queue and restored its original audio settings.
  Its archives, IPA, dSYM and QA evidence remain untouched.
- Runtime regression suite: 573 passed, 2 packaged-app checks skipped pending
  signed artifact. TypeScript and web JavaScript checks pass.
- Native macOS: compiled successfully; all 336 tests pass. The catalogue test
  now checks that the selected conversation was fetched rather than assuming
  it must be the final request before the account refresh.
- Native speech settings and transcription follow the conversation's actual
  Home, including remote employees. The upload retains the host selected before
  recording. Cross-Home runtime and native request tests pass.
- Chat model writes use a scoped conversation endpoint. Relaying the legacy
  query-style request also canonicalizes it; an older Home returns 404 rather
  than accidentally changing device defaults. Regression was reproduced before
  the fix and passed afterward. Web save/reload/inheritance passed via real UI.
- The earlier real Telegram Sol response is independently confirmed by its
  engine turn_context (gpt-6-sol, medium). Defaults were restored afterward.
- iOS normal-size model persistence and device/employee inheritance passed.
  Largest Dynamic Type exposed a real pairing problem: the primary “Open
  assistants” toolbar action moved into overflow. Its iOS action now lives in
  scrollable content. Acceptance continues; do not claim the large-text pass yet.
- Build number is now 48; no build 48 has been published yet.

## 17 October, 08:43 UTC — native UI accepted for build 48

- All three iOS model UI scenarios passed, including maximum accessibility
  text size, chat save/relaunch/cancel/inherit, and device/employee inheritance.
  The pairing primary action now stays in scrollable iOS content. No physical
  iPhone Camera or microphone result is implied by simulator coverage.
  Evidence: `.data/voice-48/ios-models-v3.xcresult` and screenshots.
- macOS Computer Use passed connection, model selection, and sending with the
  selected Sol/Ultra Fast parameters against a disposable Home. Its engine is
  synthetic; the independent real Telegram/engine evidence is recorded above.
- Actual ElevenLabs recognition was also exercised through the native composer
  using a recovered audio draft in that disposable Home. The transcript appeared
  in the editable composer before sending; editing and sending then passed.
  The proper noun was rendered as OpenStroodle, so this is not a perfect-accuracy
  claim. Screenshot: `.data/voice-48/mac-elevenlabs-preview.png`.
- Release macOS 48 compilation succeeded. Signed-package acceptance, deployment
  and Apple processing are the next gates; no build 48 is public yet.
