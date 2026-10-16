export type Channel = "api" | "telegram";

export interface Conversation {
  id: string;
  channel: Channel;
  externalId: string | null;
  title: string | null;
  codexThreadId: string | null;
  createdAt: string;
  updatedAt: string;
  profileId?: string | null;
}

export interface Message {
  id: string;
  conversationId: string;
  channel: Channel;
  direction: "inbound" | "outbound";
  replyToId: string | null;
  text: string;
  externalId: string | null;
  createdAt: string;
  status?: "queued" | "running" | "completed" | "failed";
  error?: string | null;
  kind?: "text" | "notice";
  author?: string | null;
  imported?: boolean;
  attachments?: Attachment[];
  /** Presentation metadata only. Never changes the conversation's audience or model context. */
  origin?: { channel: "api" | "telegram" | "archive"; title: string; chatId?: string; url?: string; canReply?: boolean };
  delivery?: { state: "pending" | "delivered" | "unknown" | "not_sent"; error?: string };
}

export interface Attachment { id: string; conversationId: string; name: string; mimeType: string; size: number; }

export interface TelegramChat { chatId: string; title: string; conversationId: string | null; profileId: string | null; allowedSenders: string[]; access: "approved" | "members"; replies: "instructions" | "mentions"; enabled?: boolean; }
export interface HistoryEntry { sourceId: string; date: string; author: string; direction: "inbound" | "outbound"; text: string; }

export interface EmployeeProfile {
  appearance?: import("./agent-appearance.js").AgentAppearance;
  id: string;
  name: string;
  instructions: string;
  capabilities: string[];
  /** Null with a model means ChatGPT, as stored before providers existed. */
  provider?: string | null;
  model: string | null;
  serviceTier?: string | null;
  reasoningEffort?: string | null;
  tokenLimit: number | null;
  createdAt: string;
  preview?: string | null;
  domain?: "personal" | "work";
  purpose?: string;
}

export interface EngineEvent {
  type: string;
  payload: unknown;
}

export interface CodexRunResult {
  threadId: string;
  response: string;
  events: EngineEvent[];
}

export interface CodexEngine {
  /** Native app-server input for an already running turn; false means no turn. */
  steer?(input: string, options: { threadId: string; images?: string[] }): Promise<boolean>;
  forContext?(context: string): CodexEngine;
  forAgent?(agentId: string, context: string): CodexEngine;
  run(
    input: string,
    options?: {
      threadId?: string | null;
      conversationId?: string;
      /** The inbound message this turn answers. */
      messageId?: string;
      signal?: AbortSignal;
      onEvent?: (event: EngineEvent) => void;
      profile?: string | null;
      /** The resolved provider; a turn stays on its route. */
      provider?: string | null;
      model?: string | null;
      serviceTier?: string | null;
      reasoningEffort?: string | null;
      /** Permanent employees offered as native Codex roles on this device. */
      employees?: EmployeeProfile[];
      images?: string[];
      /** Snapshotted when the queued turn starts on its execution device. */
      approvalMode?: import("./approval-mode.js").ApprovalMode;
      groupContext?: boolean;
      /** Trusted: the device owner sent this turn. Set by the server from the owner's session and by the Telegram adapter, never from a request body. */
      byOwner?: boolean;
      /** A schedule started this turn. */
      scheduled?: boolean;
      /** Verified channel identity, supplied only by the Telegram adapter. */
      telegramActor?: { userId: string; chatId: string; messageId: string };
      tools?: { definitions: DynamicTool[]; call: (name: string, args: Record<string, unknown>) => Promise<unknown> };
      onRequest?: (method: string, params: Record<string, any>) => Promise<unknown>;
    },
  ): Promise<CodexRunResult>;
  close?(): void;
  models?(refresh?: boolean): Promise<import("./model-settings.js").ModelChoice[]>;
  connections?(refresh?: boolean): Promise<Connection[]>;
  connectionNotice?: string;
  isConnected?(id: string): Promise<boolean>;
  connect?(id: string, options?: { callbackURL: string }): Promise<ServiceSignIn>;
  extensions?(): import("./extensions.js").CodexExtensions | Promise<import("./extensions.js").CodexExtensions>;
}

export interface ServiceSignIn {
  url: string | null;
  /** In-memory continuation, never serialized or exposed as a generic proxy. */
  oauth?: { complete(callback: string): Promise<void>; cancel(): void };
}

export interface DynamicTool { type: "function"; name: string; description: string; inputSchema: Record<string, unknown> }
export interface Connection { id: string; name: string; kind: "app" | "mcp"; detail?: string | null; connected: boolean; url: string | null; status?: "ready" | "sign_in" | "unavailable" | "disabled" | "available" | "unknown"; toolCount?: number; removable?: boolean; }
export interface Interaction { id: string; conversationId: string; messageId: string; title: string; detail?: string; url?: string; requestedBy?: string; questions: Array<{ id: string; question: string; options: string[] }>; }

export interface MessageInput {
  mode?: "steer" | "queue";
  conversationId?: string;
  channel: Channel;
  text: string;
  externalId?: string;
  externalChatId?: string;
  title?: string;
  /** Explicit employee chat. Delegation never changes the conversation's owner. */
  profile?: string;
  author?: string;
  /** Trusted Telegram delivery metadata, not accepted from the public message API. */
  replyToAssistant?: boolean;
  telegramSenderId?: string;
  /** Trusted adapter input: preserve group context without invoking the model. */
  contextOnly?: boolean;
  /** Background runs cannot wait forever for an interactive approval. */
  scheduled?: boolean;
  /** Trusted scheduler destination; null means app-only. Never accepted from a request body. */
  scheduleTelegramChatId?: string | null;
  /** Trusted: the device owner sent this message. Set by the server and the Telegram adapter, never from a request body. */
  byOwner?: boolean;
  attachments?: string[];
  /** Downloaded channel media; never accepted as arbitrary paths by the API. */
  uploads?: Array<{ id: string; name: string; mimeType?: string; contentBase64: string }>;
}

export interface MessageResult {
  conversationId: string;
  messageId: string;
  text: string;
  attachments?: Attachment[];
  /** The employee whose conversation is open, not a delegated helper. */
  profileId?: string;
}
