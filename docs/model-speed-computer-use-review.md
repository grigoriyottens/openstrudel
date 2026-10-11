# Models, computer use and App Review — 11 October 2026

## Model and speed

Settings → Application selects the default model and speed for the selected device. An employee's settings, including the main OpenStrudel assistant, can keep “Как на устройстве” or override both. Changing this affects the next queued turn; an already running turn keeps its settings and conversation history is retained.

The catalog comes from the selected account's official Codex `model/list`, with managed restrictions from `configRequirements/read`. Fast and Ultra Fast are offered only when advertised. The real account tested on 11 October advertises Fast (`priority`) and does not advertise Ultra Fast. “Обычная” explicitly sends the `default` tier, including when a thread previously used Fast. The synthetic UI fixture includes Ultra Fast to exercise capability-dependent controls.

The device stores defaults and optional per-employee overrides. HTTP, native clients, web, Telegram, schedules and delegated employees resolve the same choices. Each remote request routes to the employee's device and account. Loading, unavailable model/speed, retry, owner-only writes and save feedback are explicit.

## Computer use

“Сервисы и навыки” → “Управление компьютером” connects the official installed `cua_repl` provider on the employee's Mac. It uses the enabled OpenAI Computer Use installation; it does not bundle the provider, copy the owner's other plugins or reuse app permissions. If it is absent, the UI links to the official setup instructions. Linux retains commands/files/services and clearly explains that this window-control provider requires a Mac.

Connection is explicit per employee/audience. Codex requests access to individual applications through the existing interaction flow. The native IPC socket is resolved against the real user's home; sandbox grants cover only read-only executable dependencies. Configuration reloads are transactional and roll back on failure. Disconnect removes this provider and its additional read grants.

Live verification used an isolated OpenStrudel runtime and an actual managed account. It created/read `qa-computer.txt`, then used the official Computer Use tool to open Calculator, enter 17 × 23 and read 391. The ordinary per-app approval request was observed and accepted for Calculator only. A denied permission was also verified. Arbitrary applications, every browser workflow and a Mac without the provider/OS permissions have not been end-to-end validated.

## Validation

- Backend tests cover catalog restrictions, persistence and inheritance, queued turns, explicit Fast → normal transitions on the same thread, remote routing, owner checks, archive preservation, delegated employee settings, connector rollback and scoped permissions.
- Real macOS UI: model changes, speed selection, inheritance and saved feedback.
- iPhone simulator UI: device Astra/Fast, employee Sol/Ultra Fast in a synthetic catalog, then return to device defaults; server state checked after changes. Screenshots inspected.
- Web UI: capability-dependent speed choices, default and individual selections, inheritance, errors/retry and saved feedback. No console errors during the checked flows.
- TypeScript typecheck and macOS/iOS builds passed. Real-account Computer Use and review-server responses are separate from synthetic UI coverage.

Private logs, screenshots, test fixture details and reviewer credentials are retained outside Git under `.data/model-computer-review-2026-10-11/`.

## Apple review

The queued App Store version is 1.0, build 28. New TestFlight releases must not replace or cancel this submission without a deliberate release decision.

App Store Connect's published privacy label was inspected after account sign-in: six linked data categories (audio, user ID, email address, messages, other user content, photos/videos), each for app functionality. The privacy URL is correct. The app requests consent before sending relevant chat context/files to OpenAI. The iOS app is a free companion and has no hosting purchase flow or account creation.

A private, persistent connection page supplies short-lived invitations to a dedicated live server with an already authenticated AI account and synthetic employees. A real AI reply was verified. The review does not require the reviewer's own Mac or OpenAI account. Credentials and the private link must stay out of this document and source control.

The audit found stale “Build 12” review notes and store text referring to a main device and old connection steps. Revised instructions are prepared in the private evidence directory. Submission acceptance is Apple's decision; a successful technical check does not mean App Review approval.

Primary references: [Codex app-server](https://developers.openai.com/codex/app-server), [Computer Use setup](https://learn.chatgpt.com/docs/computer-use), [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (2.1 access/completeness, 3.1.3(f) free companions, 4.2.7 remote desktop distinction, 5.1 privacy).
