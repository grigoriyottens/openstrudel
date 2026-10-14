import type { query as sdkQuery } from "@anthropic-ai/claude-agent-sdk";
import type { ModelChoice } from "./model-settings.js";
import type { ProviderInfo } from "./providers.js";
import type { CodexEngine } from "./types.js";

export interface ClaudeEngineOptions {
  /** Home root; private state lives under `<root>/.data`. */
  root: string;
  /** A registry provider whose engine is "claude". */
  provider: ProviderInfo;
  /** Read at the start of every turn so a replaced key applies to the next turn. */
  key: () => string | null;
  /** Test seam for the SDK entry point. */
  query?: typeof sdkQuery;
}

/** The Claude Agent SDK behind the same CodexEngine contract. One per provider. */
export class ClaudeEngine implements CodexEngine {
  constructor(readonly options: ClaudeEngineOptions) {}
  forContext(_context: string): CodexEngine { throw new Error("Claude engine is not implemented yet"); }
  run: CodexEngine["run"] = (input, options) => this.forContext("personal").run(input, options);
  async models(): Promise<ModelChoice[]> { throw new Error("Claude engine is not implemented yet"); }
  close(): void {}
}
