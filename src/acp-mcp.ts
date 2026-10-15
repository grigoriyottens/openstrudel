import { randomBytes, timingSafeEqual } from "node:crypto";
import { createServer, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import type { CodexEngine } from "./types.js";

type Tools = NonNullable<NonNullable<Parameters<CodexEngine["run"]>[1]>["tools"]>;

/** The employee tools as a loopback MCP server (Streamable HTTP, JSON replies) for one turn.
 * Its random path and bearer token die with it, so a CLI that stores its session cannot call them later. */
export async function toolBridge(tools: Tools): Promise<{ url: string; token: string; close(): Promise<void> }> {
  const path = "/" + randomBytes(16).toString("hex"), token = randomBytes(32).toString("hex");
  const expected = Buffer.from("Bearer " + token);
  const reply = (res: ServerResponse, status: number, body?: unknown) => {
    res.writeHead(status, body === undefined ? {} : { "content-type": "application/json" }).end(body === undefined ? undefined : JSON.stringify(body));
  };
  const handle = async (message: any) => {
    const { method, params } = message ?? {};
    if (method === "initialize") return { protocolVersion: params?.protocolVersion ?? "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "openstrudel", version: "1" } };
    if (method === "ping") return {};
    if (method === "tools/list") return { tools: tools.definitions.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) };
    if (method === "tools/call") {
      if (!tools.definitions.some(d => d.name === params?.name)) return { content: [{ type: "text", text: `Unknown tool ${params?.name}` }], isError: true };
      try { return { content: [{ type: "text", text: JSON.stringify(await tools.call(params.name, params.arguments ?? {})) }] }; }
      catch (error) { return { content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }], isError: true }; }
    }
    throw Object.assign(new Error(`Method not found: ${method}`), { code: -32601 });
  };
  const server = createServer((req, res) => {
    if (req.url !== path) return reply(res, 404);
    const auth = Buffer.from(req.headers.authorization ?? "");
    if (auth.length !== expected.length || !timingSafeEqual(auth, expected)) return reply(res, 401);
    if (req.method !== "POST") return reply(res, 405);
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => { size += chunk.length; if (size > 4 << 20) req.destroy(); else chunks.push(chunk); });
    req.on("end", async () => {
      let message: any;
      try { message = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return reply(res, 400, { jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } }); }
      // Notifications and responses need no answer.
      if (message?.id === undefined) return reply(res, 202);
      try { reply(res, 200, { jsonrpc: "2.0", id: message.id, result: await handle(message) }); }
      catch (error: any) { reply(res, 200, { jsonrpc: "2.0", id: message.id, error: { code: error.code ?? -32603, message: error.message } }); }
    });
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  return { url: `http://127.0.0.1:${(server.address() as AddressInfo).port}${path}`, token,
    close: () => new Promise<void>(resolve => { server.close(() => resolve()); server.closeAllConnections(); }) };
}
