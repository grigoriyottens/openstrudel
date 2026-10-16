import { createServer, type AddressInfo } from "node:net";
import { CodexRpc } from "./rpc.js";
import type { ServiceSignIn } from "./types.js";

export const SERVICE_SIGN_IN_SECONDS = 600;

/** Codex still owns discovery, registration, PKCE, state, exchange and tokens.
 * Only the browser's callback travels back over the already paired Home link.
 * Temporary CLI overrides never rewrite the employee's MCP configuration. */
export async function serviceOAuth(input: {
  name: string; home: string; workingDirectory?: string; callbackURL: string;
  connected: () => Promise<void>; closed: () => void; signal?: AbortSignal;
}): Promise<ServiceSignIn> {
  input.signal?.throwIfAborted();
  const reservation = createServer();
  await new Promise<void>((resolve, reject) => { reservation.once("error", reject); reservation.listen(0, "127.0.0.1", resolve); });
  const port = (reservation.address() as AddressInfo).port;
  await new Promise<void>((resolve, reject) => reservation.close(error => error ? reject(error) : resolve()));
  let completed!: (value: { success: boolean }) => void;
  const outcome = new Promise<{ success: boolean }>(resolve => { completed = resolve; });
  let stopped = false, finishing = false;
  const rpc = new CodexRpc(input.home, message => {
    if (message.method === "mcpServer/oauthLogin/completed" && message.params?.name === input.name) completed({ success: message.params.success === true });
  }, undefined, () => completed({ success: false }), input.workingDirectory, {
    mcp_oauth_callback_url: input.callbackURL, mcp_oauth_callback_port: port,
  });
  const cancel = () => {
    if (stopped) return;
    stopped = true; clearTimeout(timer); input.signal?.removeEventListener("abort", cancel);
    rpc.close(); completed({ success: false }); input.closed();
  };
  const timer = setTimeout(cancel, SERVICE_SIGN_IN_SECONDS * 1000); timer.unref();
  input.signal?.addEventListener("abort", cancel, { once: true });
  try {
    if (input.signal?.aborted) { cancel(); input.signal.throwIfAborted(); }
    await rpc.initialize();
    const result = await rpc.request("mcpServer/oauth/login", { name: input.name, timeoutSecs: SERVICE_SIGN_IN_SECONDS });
    const authorization = new URL(result.authorizationUrl);
    const redirect = new URL(authorization.searchParams.get("redirect_uri") ?? "");
    const base = new URL(input.callbackURL);
    const state = authorization.searchParams.get("state");
    if (!state || redirect.protocol !== base.protocol || redirect.host !== base.host
      || !(redirect.pathname === base.pathname || redirect.pathname.startsWith(base.pathname + "/"))
      || redirect.search || redirect.hash || redirect.username || redirect.password) {
      throw new Error("Сервис не поддержал возврат в OpenStrudel. Проверьте адрес возврата в его настройках.");
    }
    return { url: authorization.href, oauth: {
      cancel,
      complete: async value => {
        if (stopped || finishing) throw new Error("Вход уже завершён или истёк. Подключите сервис ещё раз.");
        const returned = validateServiceCallback(value, redirect, state);
        // The destination comes solely from this pending Codex login. A client
        // cannot supply a host, port or arbitrary path to this request.
        const loopback = new URL(`http://127.0.0.1:${port}${redirect.pathname}`);
        loopback.search = returned.search;
        finishing = true;
        try {
          const response = await fetch(loopback, { redirect: "error", signal: AbortSignal.timeout(20_000) });
          await response.body?.cancel();
          let confirmation: ReturnType<typeof setTimeout> | undefined;
          try {
            const confirmed = await Promise.race([outcome, new Promise<{ success: boolean }>(resolve => {
              confirmation = setTimeout(() => resolve({ success: false }), 15_000); confirmation.unref();
            })]);
            if (!response.ok || !confirmed.success) throw new Error("Сервис не подтвердил вход. Попробуйте подключиться ещё раз.");
          } finally { clearTimeout(confirmation); }
          await input.connected();
        } finally { cancel(); }
      },
    } };
  } catch (error) { cancel(); throw error; }
}

export function validateServiceCallback(value: string, expected: URL, state: string): URL {
  if (value.length > 16_384) throw new Error("Некорректный ответ сервиса.");
  const url = new URL(value);
  if (url.protocol !== expected.protocol || url.host !== expected.host || url.pathname !== expected.pathname
    || url.username || url.password || url.hash || url.searchParams.getAll("state").length !== 1
    || url.searchParams.get("state") !== state || url.searchParams.getAll("code").length > 1
    || url.searchParams.getAll("error").length > 1 || url.searchParams.has("code") === url.searchParams.has("error")) {
    throw new Error("Этот ответ не относится к начатому входу. Подключите сервис ещё раз.");
  }
  return url;
}
