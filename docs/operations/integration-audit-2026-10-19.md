# Integration audit — 19 October 2026

Follow-up to [build 51 acceptance](../releases/2026-10-19-build-51.md), coordinated
with the existing `wai mcp` task. Checked the running OpenStrudel instances,
native model tool calls and Telegram readback, not just configured connectors.

## Meeting delivery

The meeting investigated in the WAI task belongs to the PERSONAL space. Its
absence from the business search is expected; no audience or access boundaries
were changed.

- WaiClaw's existing personal MCP read the recording successfully. The transcript
  was ready and the returned card matched the notification.
- The existing notification reached the configured owner's private Telegram chat
  at 13:56:53 Moscow time. OpenStrudel's durable outbox recorded delivery, and an
  independent Telegram account read returned the same actual message and card.
- The business recording search, scheduled-meeting list and both shared Zoom
  account previews succeeded through the live Wolf employee. Preview did not
  create a meeting.
- The WAI task identified the separate video delay: an internal five-upload daily
  budget had already been consumed by older recordings. It deployed the
  video-worker repair and direct playback from the existing private Storage Box.
  This task independently rechecked the original card: HTTP 200, one native
  video element and one YouTube link. The video route returned HEAD 200 with
  `video/mp4`, length 718,112,007 bytes and byte-range support; a 256-byte range
  returned HTTP 206 with the matching full length.
- The WAI task separately verified browser playback and seeking at 23:58 and
  1:50:32, and reported the YouTube copy as VERIFIED. Storage Box playback no
  longer waits for the YouTube queue. The original card and notification event
  were retained.

No notification was replayed, no second collector was installed and no owner
credential was copied into another audience.

## Observed integration coverage

| Audience | Actual checks and remaining boundary |
| --- | --- |
| WaiClaw root | Personal access and the specific recording; business access and recording search; WaiMoney Goals status, WaiTime profile and WaiGoals status all returned successfully through native tools |
| Wolf root | Business access, recordings, scheduled meetings, Zoom availability, Gmail profile, Google Calendar profile and central task reading succeeded |
| Wolf root Notion | Initially rejected the current credential with `invalid_token`; after the owner completed the normal OAuth flow, the native `notion_get_self` call succeeded |
| Wai Core Team private | Business access and native Notion profile read succeeded |
| Wai Core Team Telegram scope | Native Notion profile read succeeded. The existing business MCP advertises 79 tools; its calls require the verified Telegram participant. An app-origin test without that identity correctly omitted these tools. A new real Telegram participant turn was not sent or replayed |
| Conference manager | Native Notion profile read succeeded |
| Grant | No external MCP servers are configured. Build 51 covered basic storage, history and native memory; the later real Telegram walkthrough below found and repaired missing project materials in the group audience. External WAI knowledge access is not configured |

The owner-private business connector advertises 88 tools, personal knowledge 19,
WaiMoney 19, WaiTime 22, WaiGoals 1 and the existing Notion connection 65. Counts
describe the current catalog, not proof that every operation has been exercised.
This audit inspected 35 active audience scopes across the three servers. It did
not turn file-based assistants into copies of the owner's private integrations.

## Notion recovery and verification limits

The initial catalog still reported Notion as ready before the native thread
encountered the authentication rejection. A fresh thread-aware status then
reported `sign_in`, zero tools and a Connect action in the installed Mac app.
The user completed reauthorization in that same existing connection. Fresh status
and a real tool call both confirmed recovery; other working Notion audiences
were not reconfigured.

OpenAI's optional service directory returned an unavailable notice during this
audit. Installed Gmail/Calendar calls and configured MCP calls worked despite
that directory failure. The directory notice is not a claim that every possible
service can currently be browsed or installed.

These are point-in-time read checks. They do not certify all writes, future
deliveries, freshness of every external dataset or a shared cross-server index.
Synthetic app-only test turns were hidden after the integration checks; their
evidence and native history were retained. Those checks sent no external test
messages. The separately requested Grant group walkthrough below did.

## Grant group walkthrough

The owner subsequently requested real demonstrations in the existing Grant
Telegram group. Membership was confirmed through Telegram's `getChatMember`,
and the group's history independently confirmed the same bot was added earlier.
The group was connected to the root assistant with an empty audience workspace,
while the project materials belonged to the Grant employee's app workspace.
An online server and a successful basic storage probe had not established that
the group could actually use those materials.

The existing group was bound to the Grant employee through the normal Home API.
Its member access, reply policy and separate group audience were retained.
The previously shared project sources, corrected due-diligence directory and
working notes were copied into that audience: 1,550 files, 892,811,712 bytes,
verified byte-for-byte with recorded SHA-256 hashes. The redundant compressed
ZIP was not copied. This is an explicit project snapshot, not an automatic
cross-audience synchronization mechanism or access to the owner's other data.
The previous binding and copy receipts were saved privately for rollback.

A second issue surfaced only in the real group: Telegram reported
`can_read_all_group_messages=false`. A plain username mention was visible to
the user's account but never reached Home. An addressed `/ask@…` command did,
and the next question sent as a reply to the bot also did. This matches
[Telegram's documented privacy-mode delivery rules](https://core.telegram.org/bots/faq#what-messages-will-my-bot-get).
The first two answers arrived after approximately 25 and 18 seconds. They
identified the current corrected archive, distinguished it from the withdrawn
version, and listed five open questions with named sources and explicit gaps.
Both were read back from the user's Telegram account, independently of Home's
successful outbox receipts. These real demonstration messages remain visible.

The third question asked the bot to open an original software registration
certificate and a prior grant document. Its answer arrived in about 23 seconds,
named the exact two PDFs, and gave their dates and specific contents without
claiming that a report had been accepted or funds received. Independent PDF
text extraction confirmed the cited facts. All three turns completed and all
three outbox deliveries were recorded as delivered; the Telegram connection
remained healthy. Privacy mode was still enabled at this readback, so commands
and replies were the verified entry points at that stage.

The owner then explicitly authorized disabling privacy mode. BotFather confirmed
`DISABLED`, and an independent `getMe` returned
`can_read_all_group_messages=true`. A fourth question, sent as an ordinary
username mention without a command or reply, received a substantive answer in
six seconds. The answer turned the prior discussion into a three-point meeting
agenda and was read back from the user's Telegram account. The group retains
its `mentions` reply policy: receiving general conversation does not cause an
automatic reply to every message. No bot removal or group recreation was needed.

Private receipts are in the release worktree's
`.data/three-server-audit-2026-10-19/*integration*`, `*notion*` and
`grant-group-*` files. Meeting contents, tokenized card links and credentials
are not included in this document.
