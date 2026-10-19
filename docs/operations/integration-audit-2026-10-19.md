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
  budget had already been consumed by older recordings. That task owns the
  video-worker repair and the requested Storage Box playback. Neither video
  availability nor completion of that separate deployment is certified here.

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
| Grant | No external MCP servers are currently configured in its three active audience scopes. Its local files, history and native memory are covered by build 51 acceptance; external WAI knowledge access is not configured |

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
Synthetic app-only test turns were hidden after the checks; their evidence and
native history were retained. No external test messages were sent.

Private receipts are in the release worktree's
`.data/three-server-audit-2026-10-19/*integration*` and
`*notion*` files. Meeting contents, tokenized card links and credentials are not
included in this document.
