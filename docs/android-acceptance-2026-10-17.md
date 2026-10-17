# Android companion — implementation and physical-device acceptance

Requested on 17 October after build 48. The connected Samsung Galaxy A07
(`SM-A075F`) is available through USB. There was no Android project in main;
this is a native companion to the existing Home API, not another agent runtime.
Physical iPhone acceptance remains unavailable and is not inferred from Android.

## Work plan

1. Add a Kotlin/Jetpack Compose client using the existing Home API, invitation
   format, certificate/public-key pins, idempotency keys and paged timelines.
   Keep credentials in Android Keystore encrypted private storage. Support
   multiple Homes, save removal before network logout, and reject stale reads.
2. Make connection entry consistent: scan QR, paste a link, open a shared link,
   review the destination, connect. No credentials in logs or website queries.
3. Provide the core native journeys: employees across connected Homes; create,
   edit, hide and delete with confirmation; native chat with Telegram origins,
   pagination, retained drafts, durable sends, steer/queue/interrupt and cancel.
4. Add system file/photo selection, authenticated attachment access, microphone
   recording, Home-selected recognition and editable transcription before send.
   Keep a recoverable recording after a recognition failure.
5. Expose provider-supported model, speed and reasoning for the chat without
   changing employee/device defaults. Include connected services and schedules
   through existing Home APIs. Respect server authorization and capability
   versions; do not guess unsupported settings.
6. Check full-row tap targets, light/dark appearance, largest text, keyboard and
   system-bar insets, narrow screens, rotation, background/foreground and cold
   start on the physical Android device.
7. Run focused unit/instrumentation tests for connection validation, pinning,
   storage, late responses, duplicate sends and paging. Then test real Home
   requests, tools, audio and files on the phone using disposable employees and
   the existing private QA group. Separate fixtures from real provider results.
8. Inspect the final diff, run the relevant regression checks, merge/push verified
   changes, and retain a signed installable APK and concise evidence. Preserve
   other tasks' files, release artifacts, existing phone apps and user data.

## Initial evidence and boundaries

- Main was clean at `435dd8c`; work continues in the existing release worktree on
  `codex/android-companion`. GitHub was fetched before implementation.
- `adb devices -l` reports one authorized USB Samsung Galaxy A07.
- Existing Android SDK, Java, platform tools and Android CLI are available.
- WaiClaw (`204.168.210.10`) and Grant (`2.29.5.55`) are reachable over SSH, but
  both reject the documented root authentication with `Permission denied
  (publickey,password)`. Their release/settings cannot be inferred from Wolf.
- AiGid released the native build/audio queue. Its archives, results and app
  remain outside this task's cleanup scope. No additional simulator is needed.
- Data had 8.42 GiB available and normal memory pressure before implementation.
  Reuse Gradle/SDK caches, limit build workers, and measure during the work.

## Acceptance record

### Passed on the connected Galaxy A07

- Native release APK builds, passes release lint (zero errors), is signed with
  the dedicated Android distribution certificate and installs successfully.
  Android build 1 is independent of Apple/Home build 48.
- Twelve unit tests pass: invitation validation/redaction, persisted operation
  identifiers, certificate and SPKI pinning, expiry, redirect isolation, ETags,
  pairing receipts, relay operations, stale HTTP connection recovery and refusal
  to silently replay an ambiguous write.
- Eight physical-device instrumentation tests pass. These use isolated TLS
  fixtures: encrypted pairing/recreation, full-row navigation and retained
  drafts, duplicate-send protection, removal during a late response, editable
  transcription, per-chat model scope/local hiding, newest-answer visibility,
  confirmation/cancellation of deletion isolated to one Home, and ten consecutive multi-record TLS responses. Fixture evidence does not
  claim a real provider call. Log: `.data/android-physical-final.log`.
- Real Mac mini employee creation from the phone succeeded. A real model read
  the arithmetic request and answered **700 RUB total, 300 RUB remaining**.
- Native microphone recording went through the Home's actual ElevenLabs
  provider and appeared in the editable composer, without sending. Russian
  words and numbers were recognized; the brand name became “Open street”, so
  this is not a perfect-accuracy claim. A failed recording remains recoverable.
- The system file picker attached a synthetic text document and a red/green/blue
  image. The real model used both, returned the correct budget and correctly
  named the three colors. Authenticated image preview rendered on the phone.
- Two Homes coexisted. Removing one connection stayed removed across recreation
  and application updates. The second connection remained available.
- Light/dark themes, 200% font scaling and landscape were inspected on the
  phone. The pairing actions now occupy separate full-width rows. The signed
  app's large-text screen fits and scrolls without hiding its primary action.
- The native Google QR scanner opens its camera. A real QR was not physically
  placed in front of this phone; successful camera opening is not a decoding test.

### Defects reproduced and fixed during acceptance

- Closing a pinned TLS client could perform socket shutdown on the UI thread;
  shutdown now runs on its own existing executor.
- A new answer could appear below the viewport after a long request. The chat
  follows new replies only while the reader is at the latest messages; reading
  older history remains undisturbed. A device regression covers this.
- Optional health/account reads delayed an already successful employee creation
  or catalogue response. The actual result is now published immediately.
- Standard HTTP recovery handles a closed pooled connection, while mutating
  bodies remain one-shot. Deliberate retry uses the original operation ID.
- Pairing, OAuth callbacks, connection removal and pending uploads retain their
  scope and durable state through lifecycle changes. Unreferenced private draft
  files and downloaded copies have bounded retention; saved drafts are retained.

### Network boundary still open

The phone's external route to Wolf's nonstandard TLS ports intermittently drops
packets. A native `HttpsURLConnection` reproduces the stalled response, separately
from OkHttp. Server TCP evidence shows unacknowledged/retransmitted bytes and a
collapsed congestion window. The identical Mac mini server returns its complete
51,876-byte catalogue over USB in 69–75 ms and works over the local Wi-Fi address.
The phone's isolated TLS test also passes ten 80 KiB responses. These observations
narrow the cause to the external route, but do not establish which network
component drops traffic. No firewall, certificates, VPN or production ports were
changed speculatively. A reliable outside-network Android session remains open.
Evidence: `.data/android-usb-read.log`, `.data/android-qa/tls-stall.txt` and
`.data/android-qa/tls-packets.txt` (TCP metadata only).

### Resource guard

At the acceptance checkpoint Data had 6.37 GiB free; physical memory pressure was
normal. Android app PSS was about 116 MiB, RSS 188 MiB. The native-cache wrapper
found no eligible idle caches. Nothing was deleted to manufacture free space;
release archives, user databases, Codex history and other chats' work are intact.


### Signed-build acceptance

- The HTTPS association was deployed with an origin configuration backup, syntax
  check, exact nginx reload, documented edge sync and external health checks.
  Other app associations and the Sparkle feed remain intact. The phone reports
  `waiwai.is: verified` (not forced approval). An implicit HTTPS browser intent
  opened the native invitation review and paired the signed release successfully.
- The release survives installation updates with its encrypted connection intact.
  It loads the existing QA chat, images, files and latest answer. An attached text
  file opens through Android's standard chooser and temporary read permission.
- The real chat saved GPT-6 Sol / Fast / Low on Mac mini without changing employee
  defaults. The engine turn context independently confirms Sol / Low. One save
  lost its reply on the first attempt; a retry succeeded. No uncertain mutation
  is automatically replayed by the transport. This remains a reliability caveat.
- The live services screen shows configured services and correctly reports that
  OpenAI's public catalogue is unavailable. This is not a passed new OAuth or
  MCP/skill installation journey. Those remain separate acceptance work.

### Common Home defect discovered by Android testing

The combined real request “75 times 8; remind me here in one minute” reached Codex
intact. Its recorded output included the correct calculation as `commentary`,
then a native 60-second `sleep`, then `ANDROID_OK_17` as `final_answer`. Only the
final response was stored by Home; no schedule existed. The earlier description
that Home overwrote this calculation was inaccurate: it filtered a commentary
item as designed. The missing durable one-time scheduling path caused the model
to wait inside the turn. Fix that path with the existing clock, and keep the
immediate calculation in the actual answer. Do not count this scenario as passed.

### Publication

Android 1.0 build 1, source `f8d1246`, is pushed to `main` and published at
https://waiwai.is/openstrudel/downloads/OpenStrudel-1.0-1.apk.
The public APK and checksum manifest were downloaded and verified after atomic
publication with a timestamped backup. The Apple update feed is unchanged.
SHA-256: `a921667970be67b535c7387793dc1e4838e10570220e708e03f7b76e8631d7cf`.
The final signed app opens the attached document as `android-qa17.txt` in the
system viewer. Publication receipt: `.data/android-release-1/published.json`.

### Shared reminder fix verified for Android 2 / Home 49

Two real requests from the installed release app returned the correct calculation
and saved one-time reminders through the existing Home clock. The first survived
a graceful server restart before delivery. The second began within 3 ms of its
saved deadline and produced one reply about 19 seconds later; provider latency
remains visible. No sleep tool or duplicate reminder was used. The phone shows
both completed results without a re-enable toggle. Nine isolated physical tests
now pass, including completed/uncertain reminder presentation. These are separate
from the two real-model tests. The public release is still Android build 1 until
the build 2 publication receipt is recorded.
