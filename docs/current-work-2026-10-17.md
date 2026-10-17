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
