# Recipes and WAI Core: Telegram ↔ native Grok Bot

The owner's pilot uses a new `@wai_recipes_bridge_bot` in the existing recipes
group and a separate native Grok Bot named «Рецепты», pinned in the sidebar.
The native Bot owns the conversation, tools and memory. The standalone bridge
in `plugins/telegram-bridge` only transports messages and records delivery.

## Verified live

- The new Telegram bot received an addressed command from the intended group.
- The native webhook accepted it, and Grok Bot called `reply_to_telegram`.
  The actual recipe arrived from the new bot, independently read through the
  user's Telegram account. Dispatch to delivery took approximately 24 seconds.
- A follow-up without a quoted recipe retained the earlier no-cilantro
  condition. The bridge was restarted while this native run was pending; the
  answer arrived once, approximately 34 seconds after dispatch.
- The real Telegram UI displayed `WAI Bridge · Рецепты is typing` while waiting.
- From the Grok Bot app, the owner asked to send the word «тест». After adding
  `send_to_telegram`, Grok Bot sent precisely that word with no incoming
  Telegram request. Both its delivery receipt and the message in Telegram
  were checked. The native Bot reported storing this workflow in its memory
  and connector instructions; those storage files were not independently read.
- Authenticated live MCP discovery exposes `get_telegram_request`,
  `reply_to_telegram`, `send_to_telegram` and `get_telegram_history`.
  The HTTPS certificate validates.
  Request bodies and keys are omitted from service logs.

Telegram commands use `/ask@wai_recipes_bridge_bot`; replies to the new bot also
work with Privacy Mode enabled. Requests from the native app can simply say
«Напиши в Telegram…». A native routine can use the same outbound tool when the
owner asks for scheduled posts; the bridge has no scheduler of its own.

## Boundaries and discovered issue

The pilot transports text and quoted reply text. It does not import the old
group archive, voice recordings, photos or files. Native webhook acceptance
does not prove execution or delivery: the persisted request is complete only
after the Telegram API receipt. Ambiguous external outcomes require inspection
instead of an automatic duplicate send. Native failures after webhook
acceptance remain visible in Grok Bot's own run history.

The old WaiClaw bot also answered commands explicitly addressed to the new
bot. A regression test reproduced this. OpenStrudel now ignores commands for
another username and replies to another bot unless explicitly mentioned. This
preserves its ordinary group participation and existing scheduled recipes.
Production acceptance of that correction is recorded separately in the
release notes, rather than inferred from the pilot's successful new replies.

## Implementation checks

Seven focused bridge tests cover a real MCP client, new outbound messages,
isolation to one configured chat, duplicate updates and sends, restart recovery,
uncertain delivery, sender authorization, exact paginated history, and splitting
at Telegram's UTF-16 boundary. The selected
Telegram routing/context/continuity suites total 50 passing tests. Typecheck
and skill validation pass.

Private configuration, service deployment receipts and native webhook keys
are outside Git under `.data/recipes-bridge`. The standalone service runs on
the existing personal server in its own containers and data directory, with
automatic restart and bounded container logs.

Sources: [native webhook behavior](https://cursor.com/help/grok-bot/routines),
[plugin configuration format](https://prod.cursor.com/docs/reference/plugins).

## Exact recall and personal-agent access follow-up

A later live check exposed a genuine native-memory limitation: the Bot retained
“no cilantro” but could not recover the amount of cheese in its own first
recipe. `get_telegram_history` now reads exact requests and replies from the
existing durable delivery queue, with pagination. It creates no separate AI
memory, embedding index or automatic full-history prompt. The native Bot read
the original answer through this tool, and its updated routine then passed a
new Telegram check: the recipe for four used 1 kg zucchini, eight eggs, 200 g
cheese and 6–8 tablespoons of flour, without cilantro.

The native personal Bots also see account-wide connectors and shared owner
files. Their webhook routines run in the owner's context. Both pilots now
admit only the owner's verified Telegram sender ID before dispatch; anonymous
messages and other participants are ignored. This is not shared-agent identity
isolation. Opening the pilot to the whole group requires a native shared
execution context with suitable connector permissions. The existing Wolf
remains responsible for the team's established group workflows.

## WAI Core work pilot

The owner added the separate `@wai_core_bridge_bot` to Wai Core Team. Telegram
membership was confirmed before starting polling. The native «WAI Core · пилот»
Bot is pinned and connected to its own webhook routine and MCP bridge on the
existing work server. Wolf's bot, group configuration and schedules remain.

The native Bot read a current work meeting, the central operations document,
and the office PDF already shared in the group. It also checked both Zoom
accounts with preview only; no meeting was created. It uses the original
WaiWai and WAI Telegram sources, without copying their knowledge corpus into
the bridge.

A separate file check asked for two exact passages from page two that were
absent from the group's text summary. The Bot downloaded the original PDF and
used `pdfinfo` and `pdftotext`. Its six-page count and both passages matched
independent local extraction and visual inspection of that page. This validates
reading the actual file, rather than only its name or caption.

The work audit also found an upstream Focus parser bug: the Notion page used
numbered lists, while the MCP reader only extracted checkboxes and returned
zero tasks. The coordinated [WAI fix](https://github.com/mikwiseman/waiwai/pull/157)
was deployed and merged. Direct MCP readback and a new request through the
Telegram → Grok → Telegram path both returned all 12 real items, their four
sections and the owner's three items. Completion is correctly unknown
(`checked: null`), because the source lists have no checkbox. No Notion data
was rewritten.

The first group request reached Grok but produced an incorrect “PDF
unavailable” answer: its routine had been told to avoid WAI Telegram and looked
only in the new bridge archive. The instruction now permits reading this
group's history and files through the existing connector, while all replies
use the bot bridge. The repeated request correctly identified the budget,
first office address and a later exclusion from the conversation. The answer
was independently read in Telegram; Wolf did not duplicate it.

A separate request from the native Grok app used `send_to_telegram` without an
incoming Telegram message. Both the delivery receipt and the actual group
message were verified. Account-wide WAI Telegram instructions were restored
after checking their scope; the work-group reading restriction lives in this
Bot and routine. It is an instruction, not a substitute for access control.

Commands use `/ask@wai_core_bridge_bot`; replies to the bot also work with
Privacy Mode enabled. This is an owner-only text pilot. Reading existing files
through WAI Telegram works; direct voice/photo/file transport, delivery of
generated attachments and full replacement for every team participant are
not claimed. Private acceptance records and screenshots are in
`.data/core-bridge`.

## Personal OpenStrudel integration follow-up

The live WaiClaw root had no WAI Telegram connection and reported that absence
to the owner. The existing owner credential was connected only to its private
personal context, after a configuration snapshot. All 11 group configurations
were unchanged. Native Codex discovery then reported 29 ready Telegram tools;
its recorded tool call actually searched and found Wai Core Team. No message
or draft was created by that check.
