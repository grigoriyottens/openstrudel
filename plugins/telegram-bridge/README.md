# Telegram bridge

A small standalone transport for an existing agent. Telegram long polling sends addressed text to the agent's native webhook. The agent replies through authenticated MCP tools, or initiates a new Telegram message directly from its own app. No inference provider, copied agent memory or OpenStrudel runtime is required.

Requires Node 24+ and a public HTTPS reverse proxy. Run `node bridge.mjs /private/config.json` using `config.example.json` as the configuration shape. Add `--serve-only` during MCP setup to keep Telegram polling paused. Keep this file private; never commit real keys. Back up the SQLite queue along with configuration. Only one process may poll a bot token.

1. Create a Telegram bot with BotFather and add it to the intended group. Obtain the exact bot and chat IDs from `getMe` and an addressed `getUpdates` message.
2. Create a native agent with a webhook routine. Record the routine's URL and key in the private bridge config. HTTP 200 only means the native run started.
3. Connect the HTTPS `/mcp` endpoint using the bridge's bearer token. The plugin manifest, `mcp.json` and skill describe this connection for clients supporting Cursor-format plugins; custom remote MCP setup works without installing the package.
4. Tell the native routine to answer the webhook's `request_id` using `reply_to_telegram`. Confirm that the actual tools are available before polling Telegram.
5. Send `/ask@your_recipes_bot ...` in the group, then reply to the bot's answer. Check both Telegram and the native conversation.
6. In the native app, ask the agent to send a message to Telegram. It uses `send_to_telegram` with a unique delivery key; repeated calls and restarts preserve the same receipt. Native scheduled posts use this tool too, so the bridge needs no scheduler.

Privacy Mode can stay on: bot commands and replies to the bot work. Plain mentions depend on Telegram's Privacy Mode. Existing bots and scheduled posts remain independent. Incoming images, voice and files are not transported by this pilot.

`/health` is a public process check; authenticated `/status` reports queue states and polling freshness without message bodies. Logs contain request IDs and transitions, never tokens or message text. SQLite persists incoming work before Telegram advances its offset. Confirmed 429/5xx webhook rejections retry; ambiguous webhook delivery and ambiguous Telegram sends stop for inspection instead of duplicating messages. Native routine failures after acceptance are visible in the native conversation; the bridge cannot infer their outcome. `dispatch_unknown` may still be completed by a native callback.

Tests: `npm test -- tests/telegram-bridge.test.ts` from the repository root. They exercise an actual MCP client, chat isolation, duplicate delivery, restart recovery and Telegram's text boundary.
