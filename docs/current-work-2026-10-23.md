# OpenStrudel — current work, 23 October 2026

Principle above all: simplicity is sexy. The simplest coherent change that
fully solves the problem; no new machinery without a clear, verified benefit.

Order: first every bug and instability, then features that make OpenStrudel
best in class.

## 1. Fix bugs and instability

- [x] Every connector in every chat on all three servers (builds 55–56).
- [x] Technical failures go to Mik's DM, never into groups (build 55).
- [x] Claude works in private and employee chats on servers: `socat`,
      lost sessions (build 56); owner schedules in groups (build 57).
- [x] Rollback snapshots bounded to two per server (build 56).
- [x] Ticket search in every chat: Tutu.ru and Kiwi.com MCP (config).
- [x] Office scout delivers on Claude: `office_telegram` as an MCP service.
- [x] Build 58: the bot sees which message a reply targets; group answers
      are threaded; one answer per burst; edits are seen; captionless files
      are context; provider-switch history keeps authors; WAI News urgent
      queue runs on Claude; Claude honours per-tool blocks; the owner can
      set a group employee's rules from the group; owner notices once per
      cause and no "Восстановлено" messages (PR #62).
- [x] Crisp SOULs on all three servers, with the schedule prompts and skill
      files that would override them (applied 23.10 after build 58; backups in
      `/data/.data/owner-maintenance/souls-20261023`).
- [ ] Health audit of every chat and schedule (e.g. С днем рождения),
      and a fix for each broken one.
- [ ] Claude parity: skills readable on Claude, Рецепт дня without images,
      Calendar/Gmail/Notion on Claude (needs Mik: Composio or tokens).
- [ ] Mik: pay the ElevenLabs invoice (`past_due`; voice messages and Zoom
      transcripts stop until then); sign in Grok on each server
      (Settings → Accounts → Grok); re-sign Notion on Wolf.

## 2. Best in class

- [ ] WAI News and Startups better and faster than Grok's versions.
- [ ] Adopt the best of Grok Bots, OpenClaw, Hermes, Claude/Codex and Dots,
      starting with proactive insights, each as the smallest change that
      reuses schedules, SOULs, notices and MCP services.
- [ ] 27 October: switch the default back from Claude to ChatGPT after the
      weekly reset (scheduled local task).
