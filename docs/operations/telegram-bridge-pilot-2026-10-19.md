# Recipes: Telegram ↔ native Grok Bot

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
  `reply_to_telegram` and `send_to_telegram`. The HTTPS certificate validates.
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

Five focused bridge tests cover a real MCP client, new outbound messages,
isolation to one configured chat, duplicate updates and sends, restart recovery,
uncertain delivery, and splitting at Telegram's UTF-16 boundary. The selected
Telegram routing/context/continuity suites total 50 passing tests. Typecheck
and skill validation pass.

Private configuration, service deployment receipts and native webhook keys
are outside Git under `.data/recipes-bridge`. The standalone service runs on
the existing personal server in its own containers and data directory, with
automatic restart and bounded container logs.

Sources: [native webhook behavior](https://cursor.com/help/grok-bot/routines),
[plugin configuration format](https://prod.cursor.com/docs/reference/plugins).
