# News and Startups source review · 21 October 2026

The personal employees use the existing Codex executor, schedules, history and
files. This is a live configuration update on build 54; no additional service,
model provider, collector or memory database was introduced.

## Source of the editorial rules

The original Grok News conversation was read in the native application. The
owner's messages on 9 September at 09:18, 09:36 and 10:44 requested immediate
AI announcements, worldwide coverage, robotics, compute and energy, plus
researchers, founders and their new companies. The bot's published explanation
at 10:46 described using meaningful X engagement as a discovery signal,
admitting significant original announcements without a popularity threshold,
and combining reposts of one story.

The saved Startups transcript contains the original daily morning request,
Product Hunt and YC, current cohorts, AI/robotics without excluding strong
outliers, and no duplicates. The owner's 21 October clarification adds Hacker
News and Alliance. Later requests to remove unnecessary limits supersede the
old fixed number of cards.

These are observed conversation messages, not an export of hidden routine
instructions. No exact-copy claim is made. The original Grok routines were not
changed.

## Applied behavior

News covers original announcements and substantive discussion on X alongside
primary websites, papers, repositories and documentation. Quote/repost activity
is a reason to investigate, not proof or a universal numeric gate. The existing
X stream covers its selected company accounts; native web search extends
discovery to people and other sources. Missing metrics are not invented.
One event remains one story across X, blogs and coverage. Useful detail determines
card length and count. Technical status messages are not news cards.

News retains the 07:00 Europe/Moscow edition and the existing 15-minute review,
plus the existing event-triggered review. It keeps the shared delivery ledger,
claim/receipt handling and unknown-delivery reconciliation.

Startups checks these four source families on its existing daily 07:11
Europe/Moscow schedule:

- [Product Hunt](https://www.producthunt.com/leaderboard): dated launches and
  leaderboard, using the latest completed day when necessary.
- [Show HN](https://news.ycombinator.com/show) and
  [Launch HN](https://news.ycombinator.com/launches): original project pages and
  substantive founder/user discussion; the official HN API supplies timestamps.
- [Y Combinator](https://www.ycombinator.com/launches): launches and company
  pages, with the current cohort checked rather than hardcoded.
- [Alliance launches](https://alliance.xyz/launches) and
  [companies](https://alliance.xyz/companies): follow the company's Latest
  Product Launch link; essays provide additional context. A directory entry
  alone is not a fresh launch. Relative dates stay relative unless verified.

The four sources are a search checklist, not four mandatory cards. Repeated
projects across platforms are combined. The employee searches its existing
history rather than loading the entire archive. Missing source access is
distinguished from a successful search with nothing new. Startups editions
remain in the application.

## Deployment and verification

Profiles and the existing Startups schedule were updated through the native
Home API, then independently read back from SQLite and the application UI.
The existing News feedback file records the owner's clarification. A rollback
copy of all changed configuration is retained on the personal server.

The first native Startups run completed at 09:40:47 UTC with five cards. It
actually read Product Hunt's 21 October page and launch cards, Show HN/Launch HN
and discussions, a YC company page, and Alliance's catalog and essays. It used
the official HN API to verify timestamps. The general YC launch page returned
no text; the employee used the accessible company page and distinguished an
undated discovery from a dated launch. The first Alliance article read failed
and was explicitly omitted rather than filled in from a search snippet.

The native News preview completed at 09:41:16 UTC. It read the existing X source
ledger, then original Unitree and Jim Fan posts and supporting primary pages.
Public page data exposed likes, reposts and quote counts for both posts at the
time of the check; the underlying tool output was reviewed. The employee kept
those observations separate from evidence of product quality, checked the
publication ledger, and distinguished a recent post from an earlier model
release date. Its ten read-only tool calls included no Telegram send or claim.

The Startups settings and completed response were inspected in the installed
macOS application, including the rendered linked cards. Both employees kept
their existing schedule IDs and delivery destinations. These checks prove the
observed reads and responses, not exhaustive X coverage or future third-party
availability.

Private source observations, before/after snapshots, native execution traces
and receipts are kept under `.data/editorial-2026-10-21/` in the release worktree.

The focused Alliance recheck completed at 09:45:44 UTC. After following the
catalog's actual company and Latest Product Launch links, the employee read the
full GridPilot announcement and the launch feed, then added one verified card.
It preserved the source's relative date and correctly declined to treat
"Closed & In Pipeline" as realized monthly revenue. The source instructions now
start with Alliance Launches and follow discovered links.

The next ordinary News review was accepted by the existing scheduler for
09:45 UTC; no new schedule was needed. Public third-party pages can still fail
or return incomplete text, as observed with the general YC feed and some direct
Alliance opens. The verified path is source discovery, following primary links,
and stating any remaining gap rather than synthesizing missing facts.
