# AI providers

Status: design for branch `claude/agent-providers` (2026-10-14).

## Goal

The owner chooses who powers the employees on a device: a ChatGPT subscription (today's only path), an OpenAI API key, Anthropic, xAI Grok, Kimi, GLM, DeepSeek or OpenRouter. One choice is the device default for every employee. Any employee can override it. A new user still reaches a working employee in one step.

## What the user sees

Two concepts, both already in the app.

1. **Accounts** (Settings → Accounts). Today: ChatGPT sign-ins. New: an **API keys** section under them. "Add key…" lists the providers. Choosing one opens a sheet with one secure field, a "Get a key" link and "Connect". The key is checked with the provider before it is saved. A saved key shows only as `••••7Qa` and can be replaced or removed, never shown.
2. **Model** (Settings → General for the device default; the employee's card for one employee; the main chat's card). The model picker is grouped by connected provider. Choosing a model chooses its provider, so there is no separate provider control and no invalid provider/model pair. An employee's first row stays "As on device · Claude Fable 5.1".

First run keeps one primary action, "Sign in to OpenAI" (ChatGPT). A quiet second action, "I have an API key", opens the same key sheet. Whichever connects first powers the device automatically, with that provider's recommended model, so the user goes straight to chat. No model is chosen during onboarding.

Not built, on purpose:
- Claude.ai, SuperGrok or Kimi Code subscription sign-in. Anthropic does not allow third-party products to offer Claude.ai login (code.claude.com/docs/en/legal-and-compliance). xAI and Kimi have no public OAuth client for third-party apps.
- Silent fallback to another provider or model. Auth and billing errors stop the turn and say which provider failed and what to do.
- Base URL fields, fallback chains, per-key toggles, an "Auto" router across providers.

## Engines

The registry (`src/providers.ts`) gives every provider one engine.

- **Codex** for providers whose native API is the OpenAI Responses API: ChatGPT (sign-in), OpenAI API keys and xAI. Codex 0.156.1 takes a provider per thread: `thread/start {modelProvider, config: {"model_providers.<id>": {name, base_url, wire_api: "responses", experimental_bearer_token}}}`. Verified with a mock server: streaming, reasoning and dynamic tools round-trip, ChatGPT credentials never reach the custom provider, and the inline token is not written to disk. Codex refuses Chat Completions (`wire_api = "chat"`).
- **Claude Agent SDK** (`@anthropic-ai/claude-agent-sdk`) for Anthropic and for providers whose officially documented coding-agent integration is an Anthropic-compatible endpoint: Kimi, GLM, DeepSeek and OpenRouter (`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`). Their tools arrive as ordinary Anthropic tools, so MCP services keep working. Under Codex, every MCP tool is an OpenAI-specific `namespace` tool, which none of these vendors document.

Codex remains the main engine and the only one for ChatGPT. The Claude engine is a second implementation of the existing `CodexEngine` interface, not a second agent loop inside OpenStrudel:

| OpenStrudel | Codex | Claude Agent SDK |
|---|---|---|
| conversation thread | thread id | session id (`resume`) |
| employee tools (`update_employee`, `save_schedule`, …) | `dynamicTools` + `item/tool/call` | in-process SDK MCP server |
| approvals | `item/*/requestApproval` | `canUseTool` → the same `onRequest` methods |
| questions | `item/tool/requestUserInput` | `AskUserQuestion` → `item/tool/requestUserInput` |
| images | `localImage` | base64 image blocks |
| stop | `turn/interrupt` | `AbortController` |
| SOUL | `developerInstructions` | `systemPrompt` preset + append, sent every turn |

Isolation matches Codex: `settingSources: []`, a private `CLAUDE_CONFIG_DIR` per provider and context, auto-memory and non-essential traffic off, a stripped environment, the same workspace directory as the context. It never reads `~/.claude` or keys from the process environment.

Cost: the SDK bundles the Claude Code binary for the platform (236 MB on darwin-arm64), so the Mac app grows by that much. Each Claude turn starts one subprocess and resumes the session by id.

## Behaviour

**Resolution.** Employee selection → device default → automatic. Automatic is the ChatGPT recommended model when a ChatGPT account is signed in, otherwise the recommended model of the first connected key provider in registry order. Quota limits never switch providers.

**Routes and threads.** Each key provider is an account-shaped route `provider-<id>` with its own engine processes: `.data/providers/<id>/contexts/<ctx>` for Codex, `.data/providers/<id>/claude/<ctx>` for Claude. A turn is fixed to one route. A conversation keeps one native thread per route, exactly like ChatGPT accounts today: `codex.thread.<route>.<conversation>` and `codex.threadOwner.<conversation>`. A new route starts a fresh native thread seeded with up to 200 completed messages as quoted context. Resuming a native thread on another provider is never done, because Codex replays the previous provider's encrypted reasoning. Switching back resumes that route's own thread. Changing the model within one provider stays on the same thread.

**Delegation.** Codex delegation offers only employees on the parent's route. Codex runs a delegated role on the parent's provider and key whatever the role file says (verified), so an employee on another provider is left out rather than silently run elsewhere. Claude-engine conversations do not delegate.

**Approval modes.** "Ask" and "Approve all" behave the same on every provider. "Automatic" needs Codex's reviewer model, which exists only for ChatGPT; on other providers it fails closed and denies everything (verified). On key providers "Automatic" therefore asks, and the approval setting says so.

**Codex key providers.** No ChatGPT apps, no `serviceTier` (OpenAI API keeps it), web search only where the registry allows it, effort and context window from the registry (`model_context_window`, `model_auto_compact_token_limit` per thread). The OpenAI API catalog is Codex's own `model/list`.

**Images.** Text-only models (GLM-5.3, DeepSeek V4 Pro) receive attached images as file references only.

**Checking a key.** `models` providers: `GET {baseUrl}/models`. `messages` providers: one tiny `POST {baseUrl}/v1/messages` with the recommended model. A 2xx saves the key. 401/403 shows "The key was not accepted". Anything else shows the provider's own status and message and saves nothing.

**Errors.** A failure on a key route never invalidates a ChatGPT account and never shows the OpenAI sign-in text. A rejected key fails the turn with "Anthropic did not accept the key. Replace it in Accounts." An employee whose provider is not connected on this device (after a move or restore) keeps its choice, shows the model as unavailable, and its next turn fails with "Connect Anthropic on this device or choose another model."

**Removing a key.** The confirmation names how many employees use it. Those employees return to the device default; a device or main-chat default on that provider returns to automatic.

**Credentials.** Keys live only on the Home that runs the employees, in its private SQLite settings (`providers.<id>.key`, database mode 0600, like the Telegram bot token). They are never returned to clients, logged, put in prompts, process arguments, tool environments, backups or transfers. Codex receives a key per thread over stdin. The Claude engine passes it only in the SDK subprocess environment. "Reset this Mac" deletes them with the rest of the Home data.

**Privacy.** Codex sends third-party providers its usual request metadata (installation id, session, thread and turn ids). Each provider receives the messages of the employees that use it; the key sheet says so.

**Remote devices.** Keys and accounts are per device, routed by `?deviceId` like `/v1/accounts`. Writes are owner-only. iOS can add a key to a Home; the key is sent to that Home and stored there.

## Providers (v1)

| id | Name | Engine | Base URL | Recommended | Others |
|---|---|---|---|---|---|
| `chatgpt` | ChatGPT | Codex, sign-in | — | the account's | live `model/list` |
| `openai` | OpenAI API | Codex | `https://api.openai.com/v1` | Codex catalog default | Codex catalog |
| `xai` | xAI | Codex | `https://api.x.ai/v1` | `grok-4.7` | `grok-4.5` |
| `anthropic` | Anthropic | Claude | `https://api.anthropic.com` | `claude-fable-5-1` | Opus 5.5, Sonnet 5.5, Haiku 5.5 |
| `kimi` | Kimi | Claude | `https://api.moonshot.ai/anthropic` | `kimi-k3` | `kimi-k2.7-code` |
| `zai` | GLM | Claude | `https://api.z.ai/api/anthropic` | `glm-5.3` | `glm-5.3-flash` |
| `deepseek` | DeepSeek | Claude | `https://api.deepseek.com/anthropic` | `deepseek-v4-pro` | `deepseek-flash` |
| `openrouter` | OpenRouter | Claude | `https://openrouter.ai/api` | `anthropic/claude-opus-5.5` | GPT-6.1 Sol, Gemini 4 Argon, Grok, Kimi, GLM, DeepSeek |

`OPENSTRUDEL_PROVIDER_<ID>_BASE_URL` overrides a base URL (regional endpoints, proxies, tests).

## HTTP contract

- `GET /v1/providers[?deviceId]` → `{providers: ProviderSummary[], canManage}`, every registry provider plus `chatgpt` first. `ProviderSummary = {id, name, auth: "signin"|"key", connected: boolean, keyHint: string|null, keysUrl: string|null, usedBy: number}`. `usedBy` counts employees, main chat and device default that resolve to it.
- `PUT /v1/providers/:id` `{key}` → `{provider: ProviderSummary}`. 400 when the key is rejected, 502 when it cannot be checked. Owner only.
- `DELETE /v1/providers/:id` → `{ok: true, reset: number}`. Owner only.
- `GET /v1/settings/models[?agentId]` keeps its fields and adds `providers` (connected ones, `chatgpt` first) and `provider` on every model choice, `selection`, `defaults` and `effective`. `POST` accepts `{provider, model, serviceTier}`. `{provider: null, model: null, serviceTier: null}` still means "as on device"; for the device default `{provider: null, model: null}` means automatic.
- `GET /v1/account?agentId` reports the agent's effective route. For a key provider: `{account: {connected, email: null, planType: null, provider, providerName}, accountId: "provider-<id>", loginPending: false, canManage}`.
- `/health` adds `providers: 1`. The app hides the new controls for an older Home.

## Storage

- `employee_profiles.provider TEXT`, carried with `model` by employee archives, moves and backups.
- `models.defaults`, `models.main`: the JSON gains `provider`. A stored selection with a model and no provider means `chatgpt`.
- `providers.<id>.key` in `settings`.
