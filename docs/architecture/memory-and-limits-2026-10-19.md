# Memory, files and limits · 19 October 2026

## Decision

Use the official Codex runtime for selective memory, compaction, tools, search and execution. Keep original documents and full chat history as evidence. The owner's root employee gets a small source catalogue for its device, with read access to other employees' source workspaces, exported chat histories and generated memories. It retrieves relevant passages on demand; the corpus is not injected into every turn. Personal, work and Grant remain separate servers and knowledge domains. Group and employee turns do not inherit the root's expanded source access. Authentication stores are excluded.

The catalogue is a disposable projection of existing SQLite history and source paths, not another memory engine. Codex owns generated memories; OpenStrudel does not rewrite them, summarize every message, run a second agent loop or maintain a competing vector store. Required rules stay in employee instructions and original policy files. Source locations and dates should accompany recalled facts. Native memory can be delayed, selective or skipped when quota is low; it is not a lossless backup.

Enable `features.memories`, `memories.generate_memories` and `memories.use_memories` in each ChatGPT audience/account. Set `disable_on_external_context=false`, so real tool-assisted work can contribute. API-key providers do not get an unsupported ChatGPT memory promise. Native memory files are readable without granting access to credentials or unrelated Codex history. Add standard Poppler `pdftotext` to the Linux image because an actual family-document task failed without a PDF reader.

## Ready-made options considered

| Option | What it provides | Decision for these servers |
| --- | --- | --- |
| [Codex native memories](https://learn.chatgpt.com/docs/customization/memories) | Selective background extraction/consolidation and recall alongside native chat history and tools | Adopt. Already the execution runtime; verified configuration on the pinned CLI. Generation observed on Wolf. A generated summary on every other server is not yet claimed. |
| [Mem0 OSS](https://docs.mem0.ai/open-source/overview) | Memory add/search/update service with LLM, embeddings, vector storage and optional graph storage | Do not duplicate native memory now. Would add another authority for facts, ingestion, provider calls and storage to operate. Reconsider only for a demonstrated cross-runtime requirement. |
| [Letta](https://docs.letta.com/configuration/memory) | Agent runtime with persistent memory/files and background memory workflows | Not adopted alongside Codex. Its integrated runtime is useful when choosing that stack; adding both does not solve the observed filesystem/process failures. |
| [Graphiti](https://help.getzep.com/graphiti/getting-started/quick-start) | Temporal knowledge graph, hybrid retrieval, graph backend and extraction models | Defer. No measured temporal relationship query requires this machinery here. Preserve source facts so such an index can be built later without a migration of the source of truth. |
| [QMD](https://github.com/tobi/qmd/blob/main/README.md) | Ready CLI/MCP: BM25, vector search and local-model reranking over document collections | Evaluated 2.8.3 separately, not installed in production. A suitable candidate if corpus retrieval becomes a measured bottleneck. Evaluate hybrid retrieval on actual missed questions before adopting it; increase server capacity if the benefit warrants it. RAM alone is not a reason to reject the tool. |

QMD smoke evaluation used eight synthetic English/Russian documents, five queries, lexical mode only. Three queries returned the intended source with file and line references; two paraphrases returned nothing. CLI searches took 0.158–0.166 s after indexing. This is **not** a benchmark of QMD hybrid search or a claim that native retrieval is more accurate. It confirms that a lexical index alone does not replace a capable model choosing search terms. Current scope uses Codex's model, standard filesystem tools and `pdftotext`; there is no verified need for an additional persistent service. The owner explicitly accepts increasing server capacity when useful. Extra infrastructure should follow an observed retrieval failure, not be added speculatively. Private evaluation receipts stay outside the repository.

## Removed constraints

- Docker's 512-task cap: actual Codex sandbox launches failed with `EAGAIN` / `failed to fork` before available RAM was exhausted. Native runtimes now evict idle contexts; active turns, RPCs, initialization and sign-ins stay alive. Four is an idle-cache size, not a job/conversation limit.
- 16,000-character answer truncation. Persist and return the full answer.
- Six attachments per message/answer, including picker, paste/drop, restored drafts, speech output and Telegram tools. Existing per-file validation and delivery receipts still apply.
- Five-minute dictation/Whisper rejection. Native Parakeet already processes chunks; recording now lasts until the user finishes. Linux decode/recognition deadlines scale with the actual recording duration. Cancellation reaches the local subprocess.
- A separate 20 MB application speech limit. Application speech shares the 25 MiB attachment bound. Telegram downloads retain their upstream 20 MB limit.
- 32,000-character Telegram reply/tool/hook limit. The existing durable outbox splits messages to Telegram's real per-message limit without cutting content.
- 12,000-character SOUL and scheduled-prompt limits. Full text survives editing and archive transfer; transport size validation still applies.
- A legacy 5,000-character speech-output cap, raised to the selected [Eleven v4 API limit of 10,000](https://elevenlabs.io/docs/overview/models/), and silent truncation of the returned voice catalogue.
- 300-file plugin-package limit. Package bytes and filesystem/path validation remain bounded.

## Retained constraints and reasons

- Telegram per-message, download and API throttling constraints are upstream requirements; they are handled by chunking, explicit errors and `retry_after`.
- Input/body, individual-file, plugin-package and archive byte bounds protect the existing whole-buffer/base64 transfer paths and 2 GiB processes. Unlimited bytes would require streaming rather than deleting validation. Whole archives and ordinary messages have different transport bounds.
- Short names and labels have UI/storage validation; pagination bounds the returned page, not retained history. Context previews are bounded and explicitly link to the full original history. Generated memory is selective by design.
- CPU/RAM allocation, idle-runtime eviction, log retention, image pixel limits and offline-recognizer serialization protect observed resource budgets. These do not delete user documents or reject a job merely because another is running.
- Account/service quotas, native tool approval, audience separation, filesystem scope, authenticated connections, idempotent sending and uncertain-delivery checks remain. They protect the requested operation and its destination, not arbitrary product usage quotas.
- Network/RPC timeouts detect unreachable peers. There is no total Codex-turn timeout. The new two-minute watchdog acts only after an actual native infrastructure error followed by silence. It interrupts that turn and recycles its runtime when safe; it never blindly replays publishing or payment actions.

## Operational visibility

Known native infrastructure failures are recognized from tool outcomes, not model prose. The originating turn fails when the problem remains unresolved; the root employee receives a concise notice, and owner diagnostics expose the current incident. A successful tool recovery in the same turn can clear the failure; a later successful task produces a recovery notice. No credentials or raw tool output are copied into root notices. Intentional cancellation is not reported as an operational incident. Hidden scheduled messages can be cancelled by their existing IDs.

Telegram typing uses the official [sendChatAction](https://core.telegram.org/bots/api#sendchataction) API, refreshed every four seconds during processing. Overlapping requests share one indicator; the last completion stops it. Indicator transport failures do not prevent replies. Context-only and unauthorized input do not start it.
