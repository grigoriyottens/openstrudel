# Integrations in every chat — 22 October 2026

Source `b9d51b1` runs on Grant, Wolf and WaiClaw as image `openstrudel:54-b9d51b1`
(the build 54 image with this commit's runtime). Each server kept a rollback
snapshot in `/root/openstrudel-upgrade-54-b9d51b1-*`. Health, Telegram and data
counts were unchanged after the update.

## What was wrong

- Only the owner's main chat had services. Every employee chat and every Telegram
  group started empty, so the "wai team" group could not create a meeting. The bot
  then sent the owner to the main chat, which by design did not reach the group.
- Gmail was enabled nowhere. Account switches had left app grants in account
  homes: Wolf's second account still granted Gmail and Calendar to some chats.
- Since build 54, connecting an app inside a chat turn always returned 409.
- The 7 MB OpenAI app directory was loaded on every service list with a 4 s limit.
  It takes 24–32 s or returns 403, so every chat showed "Каталог OpenAI сейчас
  недоступен" and every list waited 4 s.
- Failed turns posted technical errors into groups (Familia, Wai Reflections,
  Wai Core Team).
- ElevenLabs answers an exhausted quota with 401. OpenStrudel called it a
  rejected key.

## What changed

- `openstrudel services all-chats on` shares the main chat's MCP services and
  ChatGPT apps with every employee and group on the Home, including new ones.
  It is off by default. A chat's own service, or a group's verified-sender
  service at the same address, wins. OAuth sign-ins and Computer Use stay where
  they were connected. Turned on for all three servers.
- App grants live only in each chat's shared configuration, after a one-time
  move of grants from account homes.
- Connecting an app works inside the turn, and only for the owner.
- Changed configuration reaches an idle runtime; a busy one is no longer refused.
- The app directory loads in the background and is cached in
  `.data/app-catalog.json`.
- Only the owner's own private chat shows a failure. Groups and other people
  see nothing; the owner gets one private notice per incident.
- An exhausted ElevenLabs quota says so, and the owner's notice names voice.

## State after the update

Each main chat has company (90 tools), mik-mcp (64), WAI personal (19, copied
from WaiClaw to Wolf and Grant), WAI Telegram (29) and the ChatGPT apps Gmail,
Google Calendar, Google Drive, Google Contacts, Notion, Linear, Slack, GitHub,
Figma, Canva and Spotify. Wolf also keeps its Notion MCP. All 36 chat audiences
listed every one of them as ready: 18 on WaiClaw, 14 on Wolf, 4 on Grant. The two
Wolf groups with WAI trust (Wai Core Team, QA) use their verified-sender company
service instead of the owner key; other groups use the owner key.

A read-only Google Calendar request in the "wai team" group audience returned the
day's events in 24 s. The app-only check turn was hidden afterwards.

Not shared on purpose: OpenAI system apps (Sites, OpenAI Platform and similar)
and the duplicate "Wai Operations", "mik-mcp" and "Foxy Telegram Bridge" apps,
which reach the same backends as the MCP services. WaiMoney, WaiTime and
WaiGoals were not restored; mik-mcp replaced them on 19 October.

## Open

- The ChatGPT Pro account (hi@wisemik.com) used 100% of its weekly limit; it
  resets about 27 October 06:30 UTC. WaiClaw and Grant have no other account.
  Wolf's second account (hi@waiwai.is) was at 96%.
- ElevenLabs used 599,995 of 600,000 credits with no overage; it resets about
  1 November.
- Anthropic by API key is ready (verified live in build 43). On Claude, employees
  get MCP services but not ChatGPT apps, Codex skills or plugins.
- Quota limits never switch providers automatically.

Private receipts are in `.data/integrations-2026-10-21/` of the release worktree.
