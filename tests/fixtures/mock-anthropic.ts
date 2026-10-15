import { createServer, type IncomingHttpHeaders } from "node:http";
import type { AddressInfo } from "node:net";

export type MockRequest = { method: string; path: string; headers: IncomingHttpHeaders; body: any };
export type MockReply = { text: string } | { tool: { name: string; input: Record<string, unknown> } } | { status: number; type: string; message: string };

/** A local Anthropic Messages endpoint for the real Claude Code binary. Every request is logged. */
export async function mockAnthropic(reply: (request: MockRequest) => MockReply) {
  const requests: MockRequest[] = [];
  let sequence = 0;
  const server = createServer((req, res) => {
    let raw = "";
    req.on("data", chunk => { raw += chunk; });
    req.on("end", () => {
      let body: any = raw;
      try { body = raw ? JSON.parse(raw) : null; } catch {}
      const request = { method: req.method ?? "GET", path: req.url ?? "/", headers: req.headers, body };
      requests.push(request);
      const path = request.path.split("?")[0];
      if (path === "/v1/messages/count_tokens") return json(res, 200, { input_tokens: 1 });
      if (path !== "/v1/messages") return json(res, 404, { type: "error", error: { type: "not_found_error", message: "Not found" } });
      const answer = reply(request);
      if ("status" in answer) return json(res, answer.status, { type: "error", error: { type: answer.type, message: answer.message } });
      const id = `msg_${++sequence}`, model = body?.model ?? "mock";
      const block = "text" in answer ? { type: "text", text: answer.text } : { type: "tool_use", id: `toolu_${sequence}`, name: answer.tool.name, input: answer.tool.input };
      const stop = "text" in answer ? "end_turn" : "tool_use";
      const usage = { input_tokens: 10, output_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 };
      if (!body?.stream) return json(res, 200, { id, type: "message", role: "assistant", model, content: [block], stop_reason: stop, stop_sequence: null, usage });
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", "request-id": `req_${sequence}` });
      const send = (event: string, data: unknown) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      send("message_start", { type: "message_start", message: { id, type: "message", role: "assistant", model, content: [], stop_reason: null, stop_sequence: null, usage: { ...usage, output_tokens: 1 } } });
      send("content_block_start", { type: "content_block_start", index: 0, content_block: block.type === "text" ? { type: "text", text: "" } : { ...block, input: {} } });
      send("content_block_delta", { type: "content_block_delta", index: 0, delta: block.type === "text" ? { type: "text_delta", text: answer.text } : { type: "input_json_delta", partial_json: JSON.stringify(block.input) } });
      send("content_block_stop", { type: "content_block_stop", index: 0 });
      send("message_delta", { type: "message_delta", delta: { stop_reason: stop, stop_sequence: null }, usage: { output_tokens: 5 } });
      send("message_stop", { type: "message_stop" });
      res.end();
    });
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return { url, requests, close: () => new Promise<void>(resolve => { server.closeAllConnections(); server.close(() => resolve()); }) };
}

function json(res: import("node:http").ServerResponse, status: number, value: unknown) {
  res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(value));
}
