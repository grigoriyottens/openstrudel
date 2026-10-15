import { expect, it } from "vitest";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { toolBridge } from "../src/acp-mcp.js";

const tools = (seen: unknown[] = []) => ({ definitions: [
  { type: "function" as const, name: "save_schedule", description: "Save", inputSchema: { type: "object", properties: { id: { type: ["string", "null"] }, cron: { type: "string" } }, required: ["id", "cron"], additionalProperties: false } },
  { type: "function" as const, name: "list_employees", description: "List", inputSchema: { type: "object", properties: {}, required: [], additionalProperties: false } },
], call: async (name: string, args: Record<string, unknown>) => { seen.push([name, args]); if (name === "list_employees") throw new Error("Список недоступен"); return { saved: true }; } });
const post = (url: string, token: string, method = "tools/list") => fetch(url, { method: "POST", body: JSON.stringify({ jsonrpc: "2.0", id: 1, method }),
  headers: { "content-type": "application/json", accept: "application/json, text/event-stream", authorization: `Bearer ${token}` } });

it("serves the employee tools to an MCP client that holds the turn's token", async () => {
  const seen: unknown[] = [];
  const bridge = await toolBridge(tools(seen));
  expect(bridge.url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/[a-f0-9]{32}$/);
  expect(bridge.token).toMatch(/^[a-f0-9]{64}$/);
  const client = new Client({ name: "test", version: "1" });
  await client.connect(new StreamableHTTPClientTransport(new URL(bridge.url), { requestInit: { headers: { authorization: `Bearer ${bridge.token}` } } }));
  const { tools: listed } = await client.listTools();
  expect(listed.map(t => t.name)).toEqual(["save_schedule", "list_employees"]);
  expect(listed[0]).toMatchObject({ description: "Save", inputSchema: { properties: { id: { type: ["string", "null"] }, cron: { type: "string" } }, required: ["id", "cron"] } });
  expect(await client.callTool({ name: "save_schedule", arguments: { id: null, cron: "0 9 * * *" } })).toMatchObject({ content: [{ type: "text", text: '{"saved":true}' }] });
  expect(await client.callTool({ name: "list_employees", arguments: {} })).toMatchObject({ isError: true, content: [{ type: "text", text: "Список недоступен" }] });
  expect(await client.callTool({ name: "delete_everything", arguments: {} })).toMatchObject({ isError: true });
  expect(seen).toEqual([["save_schedule", { id: null, cron: "0 9 * * *" }], ["list_employees", {}]]);
  await client.close();
  await bridge.close();
});

it("refuses another token or path, and is gone once the turn ends", async () => {
  const bridge = await toolBridge(tools()), other = await toolBridge(tools());
  expect(other.url).not.toBe(bridge.url);
  expect(other.token).not.toBe(bridge.token);
  expect((await post(bridge.url, other.token)).status).toBe(401);
  expect((await post(new URL("/" + "0".repeat(32), bridge.url).href, bridge.token)).status).toBe(404);
  expect((await fetch(bridge.url, { headers: { authorization: `Bearer ${bridge.token}` } })).status).toBe(405);
  const listed = await post(bridge.url, bridge.token);
  expect(listed.status).toBe(200);
  expect((await listed.json()).result.tools).toHaveLength(2);
  await Promise.all([bridge.close(), other.close()]);
  await expect(post(bridge.url, bridge.token)).rejects.toThrow();
});
