# AI providers

Status: design for branch `claude/agent-providers` (2026-10-14).

## Goal

The owner chooses who powers the employees on a device: a ChatGPT subscription (today's only path), an OpenAI API key, Anthropic, xAI Grok, Kimi, GLM, DeepSeek or OpenRouter. One choice is the device default for every employee. Any employee can override it. A new user still reaches a working employee in one step.

## What the user sees

Two concepts, both already in the app.

1. **Accounts** (Settings → Accounts). Today: ChatGPT sign-ins. New: an **API keys** section under them. "Add key…" lists the providers. Choosing one opens a sheet with one secure field, a "Get a key" link and "Connect". The key is checked with the provider before it is saved. A saved key shows only as `••••7Qa` and can be replaced or removed, never shown. The section appears only while the chosen device answers, so a key is never offered to a device that is offline.
2. **Model** (Settings → General for the device default; the employee's card for one employee; the main chat's card). The model picker is grouped by connected provider. Choosing a model chooses its provider, so there is no separate provider control and no invalid provider/model pair. When more than one provider is connected, the closed picker and its first row name the provider too, e.g. "GPT-6.1 Sol · OpenAI API", because ChatGPT and an OpenAI key share model names and OpenRouter repeats other vendors' names. Automatic says "Recommended by OpenAI" only for the default in OpenAI's own catalog. For other providers the registry's pick is ours, so it says "Recommended".

The employee card shows the OpenAI account choice only while the employee runs on ChatGPT.

First run keeps one primary action, "Sign in to OpenAI" (ChatGPT). A quiet second action, "I have an API key", opens the same key sheet. A connected key powers the device with that provider's recommended model, so the user goes straight to chat. An expired ChatGPT sign-in still counts as signed in, and a saved ChatGPT model ignores new keys. In those cases the app sets the device default to the key's recommended model and returns a main chat that is set to a ChatGPT model to "As on device". The user picks no model during onboarding. A key added later in Accounts changes no model, so the ChatGPT sign-in notice also says to choose a model on an API key in the employee's settings.

Not built, on purpose:
- Claude.ai subscription sign-in. Anthropic does not allow third-party products to offer Claude.ai login (code.claude.com/docs/en/legal-and-compliance). Subscriptions that are allowed are described under [Subscriptions](#subscriptions).
- Silent fallback to another provider or model. Auth and billing errors stop the turn and say which provider failed and what to do.
- Base URL fields, fallback chains, per-key toggles, an "Auto" router across providers.

## Engines

The registry (`src/providers.ts`) gives every provider one engine.

- **Codex** for providers whose native API is the OpenAI Responses API: ChatGPT (sign-in), OpenAI API keys and xAI. Codex 0.156.1 takes a provider per thread: `thread/start` and `thread/resume` with `{modelProvider: "openstrudel-<id>", config: {"model_providers.openstrudel-<id>": {name, base_url, wire_api: "responses", experimental_bearer_token}}}`. The prefix is needed because Codex reserves ids such as `openai`. Verified with a mock server: streaming, reasoning and dynamic tools round-trip, ChatGPT credentials never reach the custom provider, and the inline token is not written to disk. Codex refuses Chat Completions (`wire_api = "chat"`).
- **Claude Agent SDK** (`@anthropic-ai/claude-agent-sdk`) for Anthropic and for providers whose officially documented coding-agent integration is an Anthropic-compatible endpoint: Kimi, GLM, DeepSeek and OpenRouter (`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`). The SDK sends MCP tools as ordinary Anthropic tools. Under Codex, every MCP tool is an OpenAI-specific `namespace` tool, which none of these vendors document.

Codex remains the main engine and the only one for ChatGPT. The Claude engine is a second implementation of the existing `CodexEngine` interface, not a second agent loop inside OpenStrudel:

| OpenStrudel | Codex | Claude Agent SDK |
|---|---|---|
| conversation thread | thread id | session id (`resume`) |
| employee tools (`update_employee`, `save_schedule`, …) | `dynamicTools` + `item/tool/call` | in-process SDK MCP server |
| approvals | `item/*/requestApproval` | `canUseTool` → the same `onRequest` methods |
| questions | `item/tool/requestUserInput` | `AskUserQuestion` → `item/tool/requestUserInput` |
| images | `localImage` | base64 image blocks |
| stop | `turn/interrupt` | `Query.interrupt()`; `AbortController` only when the interrupt fails or the engine closes |
| MCP services | `mcp_servers` in the context's Codex config | a private 0600 `--mcp-config` file per turn, never inline arguments |
| SOUL | `developerInstructions` | `systemPrompt` preset + append, sent every turn |

Isolation matches Codex: `settingSources: []`, a private `CLAUDE_CONFIG_DIR` per provider and context, auto-memory and non-essential traffic off, a stripped environment, the same workspace directory as the context. It never reads `~/.claude` or keys from the process environment. Commands run in the CLI sandbox, which cannot read the Home's `.data` folder outside the workspace. A path is checked after links are followed, so a link cannot lead an edit out of the workspace.

Cost: the SDK bundles the Claude Code binary for the platform (236 MB on darwin-arm64), so the Mac app grows by that much. Each Claude turn starts one subprocess and resumes the session by id.

## Subscriptions

A subscription is used only the way its vendor documents for other apps. OpenStrudel never handles a subscription token itself.

- **Kimi Code and GLM Coding Plan** are ordinary API-key providers on the Claude engine, because both vendors document their plan keys for the real Claude Code. The key comes from the vendor's console and goes through the existing key sheet. Kimi Code is its own provider (`https://api.kimi.ai/coding`, `x-api-key`), separate from the pay-as-you-go Kimi platform. Kimi Code answers any client but a coding agent with 403, so its key is saved without a check and a wrong key shows on the first turn. GLM's endpoint already is the Coding Plan route.
- **Grok (SuperGrok, X Premium)** runs xAI's own agent, Grok Build (`grok --no-auto-update --sandbox openstrudel agent stdio`, pinned `@xai-official/grok`), over ACP, the way Zed hosts it. The vendor's agent owns its sign-in, token refresh, permissions and memory. OpenStrudel runs it in the employee's workspace with a private home under Grok's own kernel sandbox: a custom profile in that home's `sandbox.toml` extends `strict`, so Grok and every command it starts read only the workspace, system paths, installed tools (`/opt/homebrew`, `/usr/local`) and its home, and write only the workspace, its home and temp folders. Grok refuses to start when it cannot apply that profile. It never gets OpenStrudel keys or data. As with the Claude engine, reads outside the workspace are refused, changes inside it need nobody, and "Approve all" never changes files beyond it. OpenStrudel passes the employee tools as MCP, forwards its other permission requests to the approval UI with "allow once" or "reject once" only (never "always allow"), and resumes its sessions for continuity. Grok runs only the owner's own chats and schedules; a colleague's or a group's turn is refused with a pointer to an xAI key. The xAI API key provider stays on Codex for pay-as-you-go use.

**What the user sees.** Settings → Accounts has a small «Подписки» section with one row, Grok. «Войти» starts Grok's device-code sign-in on the chosen device and shows the same card as ChatGPT: the code, «Скопировать код», «Открыть страницу входа» and «Отменить вход», polled every 2 seconds. A signed-in row says «Вход выполнен» and offers «Выйти…» with a confirmation. The section is hidden unless `/health` reports `subscriptionsVersion: 1`. The model picker names the route, e.g. "Grok 4.7 · подписка Grok" beside "Grok 4.7 · xAI". An employee whose Grok sign-in is gone shows «Нужен вход в Grok».

**Personal use.** Moonshot and Z.ai license these plans to one person's own interactive work, and Z.ai also names bots. Schedules, Telegram groups and colleagues can break those rules. OpenStrudel does not block them; the API keys section says once: «Подписки Kimi Code и GLM Coding Plan — только для личного использования: расписания и ответы другим людям могут нарушать правила сервиса.»

**Packaging.** Grok Build 1.0.52 for darwin-arm64 ships as a 48 MB compressed binary that unpacks to 172 MB, and the ACP client adds 6 MB. Kimi Code and GLM add nothing.

## Behaviour

**Resolution.** Employee selection → device default → automatic. Automatic is the ChatGPT recommended model when a ChatGPT account is signed in, otherwise the recommended model of the first connected key provider in registry order. Quota limits never switch providers.

**Routes and threads.** Each key provider is an account-shaped route `provider-<id>` with its own engine processes: `.data/providers/<id>/contexts/<ctx>` for Codex, `.data/providers/<id>/claude/<ctx>` for Claude. A turn is fixed to one route. A conversation keeps one native thread per route, exactly like ChatGPT accounts today: `codex.thread.<route>.<conversation>` and `codex.threadOwner.<conversation>`. A new route starts a fresh native thread seeded with up to 200 completed messages as quoted context. Resuming a native thread on another provider is never done, because Codex replays the previous provider's encrypted reasoning. Switching back resumes that route's own thread, and the turns made on other providers since that thread last ran are added to the next input as quoted context. Changing the model within one provider stays on the same thread. Replacing a key with a different key, or removing it, drops that route's native threads, because a key from another organization cannot resume them. Claude providers also get a Codex home at `.data/providers/<id>/contexts/<ctx>`, which is used only to manage Services.

**Delegation.** Codex delegation offers only employees whose resolved provider is the parent's provider. ChatGPT accounts are not told apart. Codex runs a delegated role on the parent's provider and key whatever the role file says (verified), so an employee on another provider is left out rather than silently run elsewhere. Claude-engine conversations do not delegate.

**Approval modes.** "Automatic" needs Codex's reviewer model, which exists only for ChatGPT. On other providers the reviewer denies everything (verified), so on key providers "Automatic" asks, and the approval setting says so. On the Claude engine the modes work as follows:
- In both modes, files inside the workspace can be read without asking, and commands run in the sandbox without asking. Outside group chats, files inside the workspace can also be changed without asking.
- "Ask" asks the owner before a command that needs to leave the sandbox, a change outside the workspace and a service tool. It refuses reads outside the workspace.
- "Approve all" runs service tools without asking. It refuses commands outside the sandbox and reads or changes outside the workspace, and the turn fails when the sandbox is not available.
- Group chats get no commands and no file changes.

**Services on Claude providers.** The Claude engine loads the context's MCP services from the same files as Codex: the employee's services, the services the installer set up, and the Telegram group services for a verified sender only. It does not load SKILL.md skills, Codex plugins, ChatGPT apps or Computer Use. Browser sign-in for a service is not available there, so the owner adds such a service with an access key. The Services and skills screen still lists skills and plugins for these employees and says that they apply only on Codex providers.

**Codex key providers.** No ChatGPT apps, no `serviceTier` (OpenAI API keeps it), web search only where the registry allows it, and the registry's context window per thread (`model_context_window`, `model_auto_compact_token_limit`). The OpenAI API catalog is Codex's own `model/list` with its reasoning efforts; xAI models run with medium effort.

**Images.** Text-only models (GLM-5.3, DeepSeek V4 Pro) receive attached images as file references only.

**Checking a key.** Codex providers get `GET {baseUrl}/models`. Claude providers get one tiny `POST {baseUrl}/v1/messages` with the recommended model. A 2xx saves the key. 401 or 403 shows "The key was not accepted". Any other status shows the provider's own status and message, and nothing is saved. A network failure says the provider could not be reached.

**Errors.** A failure on a key route never invalidates a ChatGPT account and never shows the OpenAI sign-in text. A rejected key fails the turn with "Anthropic did not accept the key. Replace it in Accounts." A 402, a 429 or a quota message says the key's limit or balance ran out. Any other failed Claude turn names the provider and its short error. A Telegram group hears about a failing key once, until a turn succeeds, as with a ChatGPT outage. An employee whose provider is not connected on this device (after a move or restore) keeps its choice, shows the model as unavailable, and its next turn fails with "Connect Anthropic on this device or choose another model."

**Removing a key.** `usedBy` counts employees, the main chat and the device default together, so the confirmation calls the number "employees and settings". Employees and a main chat set to that provider return to "As on device", and a device default set to it returns to Automatic.

**Credentials.** Keys live only on the Home that runs the employees, in its private SQLite settings (`providers.<id>.key`, database mode 0600, like the Telegram bot token). They are never returned to clients, logged, or put in prompts, process arguments or tool environments. Codex receives a key per thread over stdin. The Claude engine passes it only in the SDK subprocess environment, and the CLI removes it from the environment of commands and services. A key for another device is relayed only while that device answers. The primary holds it in memory, never in its command log. A device that is offline, or does not confirm within 12 seconds, fails the write with 503, so a key never waits in the command queue, a Home backup or a transfer. Local rollback snapshots (`scripts/backup-local-state.py`) copy the SQLite database, so they hold the keys as they hold the Telegram bot token. "Reset this Mac" deletes the keys with the rest of the Home data.

**Privacy.** Codex sends third-party providers its usual request metadata (installation id, session, thread and turn ids). Each provider receives the messages of the employees that use it; the key sheet says so.

**Remote devices.** Keys and accounts are per device, routed by `?deviceId` like `/v1/accounts`. Writes are owner-only. iOS can add a key to a Home, and the key is sent to that Home and stored there. A device that does not answer shows the error and saves nothing.

## Providers (v1)

| id | Name | Engine | Base URL | Recommended | Others |
|---|---|---|---|---|---|
| `chatgpt` | ChatGPT | Codex, sign-in | none | the account's | live `model/list` |
| `openai` | OpenAI API | Codex | `https://api.openai.com/v1` | Codex catalog default | Codex catalog |
| `anthropic` | Anthropic | Claude | `https://api.anthropic.com` | `claude-fable-5-1` | Opus 5.5, Sonnet 5.5, Haiku 5.5 |
| `xai` | xAI | Codex | `https://api.x.ai/v1` | `grok-4.7` | `grok-4.5` |
| `kimi` | Kimi | Claude | `https://api.moonshot.ai/anthropic` | `kimi-k3` | `kimi-k2.7-code` |
| `zai` | GLM | Claude | `https://api.z.ai/api/anthropic` | `glm-5.3` | `glm-5.3-flash` |
| `deepseek` | DeepSeek | Claude | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-flash` |
| `openrouter` | OpenRouter | Claude | `https://openrouter.ai/api` | `anthropic/claude-opus-5.5` | GPT-6.1 Sol, Gemini 4 Argon, Grok, Kimi, GLM, DeepSeek |

Rows are in registry order, which decides Automatic and the order in Accounts. `OPENSTRUDEL_PROVIDER_<ID>_BASE_URL` overrides a base URL (regional endpoints, proxies, tests).

## HTTP contract

- `GET /v1/providers[?deviceId]` → `{providers: ProviderSummary[], canManage}`, every registry provider plus `chatgpt` first. `ProviderSummary = {id, name, auth: "signin"|"key", connected: boolean, keyHint: string|null, keysUrl: string|null, usedBy: number}`. `usedBy` counts the employees, the main chat and the device default that resolve to it.
- `PUT /v1/providers/:id` `{key}` → `{provider: ProviderSummary}`. 400 when the key is rejected, 502 when it cannot be checked, 503 when the `?deviceId` device is offline or does not confirm within 12 s (nothing is queued). Owner only.
- `DELETE /v1/providers/:id` → `{ok: true, reset: number}`. Owner only.
- `GET /v1/settings/models[?agentId]` keeps its fields and adds `providers` (connected ones, `chatgpt` first) and `provider` on every model choice, `recommended`, `selection`, `defaults` and `effective`. `POST` accepts `{provider, model, serviceTier}`. `{provider: null, model: null, serviceTier: null}` still means "as on device"; for the device default `{provider: null, model: null}` means automatic.
- `POST /v1/profiles` accepts `{provider, model}` with the same checks as the model settings: owner only, a connected provider and a model it offers.
- `GET /v1/extensions` adds a `notice` for an employee on a Claude-engine provider. `POST /v1/connections/connect` answers 409 there, because browser sign-in is not available.
- `GET /v1/account?agentId` reports the agent's effective route. For a key provider: `{account: {connected, email: null, planType: null, provider, providerName}, accountId: "provider-<id>", loginPending: false, canManage}`.
- `/health` adds `providers: 1`. The app hides the new controls for an older Home. `subscriptionsVersion: 1` adds the Grok subscription; `providers` stays 1, so apps already shipped keep their API-key screens.
- Grok is listed in `GET /v1/providers` as `{id: "grok", name: "Grok", auth: "signin", keyHint: null, keysUrl: null}`. Its sign-in, owner only and routed by `?deviceId` (a device that does not answer fails with 503, nothing is queued):
  - `POST /v1/providers/grok/login` → `{type: "device", loginId, verificationUrl, userCode}`.
  - `GET /v1/providers/grok/login/:loginId` → `{loginId, status: "pending"|"completed"|"failed"|"canceled", error?}`. `error` is shown as is, e.g. a plan that does not include Grok Build.
  - `DELETE /v1/providers/grok/login/:loginId` cancels it.
  - `POST /v1/providers/grok/logout` → `{ok: true, reset}`, resetting employees like removing a key.
  - `GET /v1/account?agentId` for an employee on Grok reports `provider: "grok"`, so the app asks for a sign-in instead of a key.

## Storage

- `employee_profiles.provider TEXT`, carried with `model` by employee archives, moves and backups. When a Mac joins another Home, its main chat becomes an employee with the chat's provider and model.
- `models.defaults`, `models.main`: the JSON gains `provider`. A stored selection with a model and no provider means `chatgpt`.
- `providers.<id>.key` in `settings`.
