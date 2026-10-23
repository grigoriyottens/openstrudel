import { afterEach, expect, it, vi } from "vitest";
const wire = vi.hoisted(() => ({ request: vi.fn(), notify: undefined as undefined | ((message: any) => void) }));
vi.mock("../src/rpc.js", () => ({ CodexRpc: class {
  closed = false;
  constructor(_home: unknown, notify: (message: any) => void) { wire.notify = notify; }
  initialize = async () => undefined;
  request = wire.request;
  close() { this.closed = true; }
} }));
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { CodexEngineAdapter } from "../src/codex.js";
afterEach(() => {wire.request.mockReset();vi.useRealTimers();});

it("releases a silent turn after native tool exhaustion without timing out ordinary long work",async()=>{
  vi.useFakeTimers();
  wire.request.mockImplementation(async(method:string)=>{
    if(method==="configRequirements/read")return {requirements:null};
    if(method==="model/list")return {data:[]};
    if(method==="thread/start")return {thread:{id:"resource-thread"}};
    if(method==="turn/start")return {turn:{id:"t"}};
    if(method==="turn/interrupt")return {};
    throw Error(method);
  });
  const engine=new CodexEngineAdapter();
  const pending=engine.run("read a file");
  const rejected=expect(pending).rejects.toThrow("ресурсов");
  await vi.waitFor(()=>expect(wire.request.mock.calls.some(([m])=>m==="turn/start")).toBe(true));
  await vi.advanceTimersByTimeAsync(600_000);
  expect(engine.busy).toBe(true);
  wire.notify?.({method:"item/completed",params:{threadId:"resource-thread",item:{type:"commandExecution",exitCode:1,aggregatedOutput:"bwrap: Creating new namespace failed: Resource temporarily unavailable"}}});
  await vi.advanceTimersByTimeAsync(120_000);
  await rejected;
  expect(engine.busy).toBe(false);
  expect(wire.request.mock.calls.some(([m])=>m==="turn/interrupt")).toBe(true);
  engine.close();
});

it("uses the account default and refreshes it without changing explicit choices",async()=>{
  let catalog:any[]=[{model:'recommended',isDefault:true,defaultReasoningEffort:'high'},{model:'explicit',defaultReasoningEffort:'low'}];
  wire.request.mockImplementation(async(method:string,params:any)=>{
    if(method==='configRequirements/read')return {requirements:null};
    if(method==='model/list')return {data:catalog};
    if(method==='thread/start'||method==='thread/resume')return {thread:{id:'recommended-thread'}};
    if(method==='thread/unsubscribe')return {};
    if(method==='turn/start') {queueMicrotask(()=>wire.notify?.({method:'turn/completed',params:{threadId:params.threadId,turn:{status:'completed'}}}));return {turn:{id:'turn'}};}
    throw new Error(method);
  });
  const engine=new CodexEngineAdapter();
  try {
    await engine.run('Automatic',{model:null,serviceTier:'default'});
    expect(wire.request.mock.calls.filter(([m])=>m==='turn/start').at(-1)?.[1]).toMatchObject({model:'recommended',effort:'high'});
    await engine.run('Explicit',{threadId:'recommended-thread',model:'explicit',serviceTier:'default'});
    expect(wire.request.mock.calls.filter(([m])=>m==='turn/start').at(-1)?.[1]).toMatchObject({model:'explicit',effort:'low'});
    catalog=[]; await engine.models(true);
    await engine.run('Fallback',{threadId:'recommended-thread',model:null,serviceTier:'default'});
    expect(wire.request.mock.calls.filter(([m])=>m==='turn/start').at(-1)?.[1]).toMatchObject({model:'gpt-6.1-sol',effort:'medium'});
  } finally {engine.close();}
});

it("steers the current native turn with its expected id and does not start another turn", async () => {
  wire.request.mockImplementation(async (method: string) => {
    if (method === "thread/start") return { thread: { id: "steer-thread" } };
    if (method === "turn/start") return { turn: { id: "running-turn" } };
    if (method === "turn/steer") return { turnId: "running-turn" };
    if (method === "configRequirements/read") return {requirements:null};
    if (method === "model/list") return {data:[]};
    throw new Error(method);
  });
  const engine = new CodexEngineAdapter();
  const pending = engine.run("Draft");
  await vi.waitFor(() => expect(wire.request.mock.calls.some(([m]) => m === "turn/start")).toBe(true));
  expect(await engine.steer("Keep it shorter", { threadId: "steer-thread", images: ["/tmp/fixture.png"] })).toBe(true);
  expect(wire.request.mock.calls.find(([m]) => m === "turn/steer")?.[1]).toEqual({ threadId: "steer-thread", expectedTurnId: "running-turn", input: [{ type: "text", text: "Keep it shorter" }, { type: "localImage", path: "/tmp/fixture.png" }] });
  wire.notify?.({ method: "turn/completed", params: { threadId: "steer-thread", turn: { status: "completed" } } });
  await pending;
  expect(await engine.steer("Late input", { threadId: "steer-thread" })).toBe(false);
  expect(wire.request.mock.calls.filter(([m]) => m === "turn/start")).toHaveLength(1);
  engine.close();
});

it("changes approval policy on resume without replaying identity or silently approving a pending request",async()=>{
  wire.request.mockImplementation(async(method:string,params:any)=>{
    if(method==="thread/start"||method==="thread/resume")return {thread:{id:"approval-thread"}};
    if(method==="thread/unsubscribe")return {};
    if(method==="turn/start"){
      queueMicrotask(()=>wire.notify?.({method:"turn/completed",params:{threadId:params.threadId,turn:{status:"completed"}}}));
      return {turn:{id:"turn"}};
    }
    if (method === "configRequirements/read") return {requirements:null};
    if (method === "model/list") return {data:[]};
    throw new Error(method);
  });
  const engine=new CodexEngineAdapter({config:{mcp_servers:{fixture:{command:"test",enabled:false}}}});
  try {
    const first=await engine.run("First");
    await engine.run("Second",{threadId:first.threadId,approvalMode:"auto",groupContext:true});
    await engine.run("Third",{threadId:first.threadId,approvalMode:"approve_all",groupContext:true});
    const resumes=wire.request.mock.calls.filter(([m])=>m==="thread/resume").map(([,p])=>p);
    expect(resumes[0].approvalsReviewer).toBe("auto_review");
    expect(resumes[0].approvalPolicy.granular.request_permissions).toBe(false);
    expect(resumes[1].approvalPolicy).toBe("never");
    expect(resumes[1].config['mcp_servers.fixture.default_tools_approval_mode']).toBe("approve");
    expect(resumes[1].config.mcp_servers.fixture.enabled).toBe(false);
    expect(wire.request.mock.calls.filter(([m])=>m==="thread/unsubscribe")).toHaveLength(2);
    expect(wire.request.mock.calls.some(([m])=>m==="thread/inject_items")).toBe(false);
  }finally{engine.close();}
});

it("sends identity as developer instructions and refreshes it when the employee changes", async () => {
  wire.request.mockImplementation(async (method: string, params: any) => {
    if (method === "thread/start" || method === "thread/resume") return {thread:{id:"identity-thread"}};
    if (method === "thread/inject_items") return {};
    if (method === "turn/start") {
      queueMicrotask(() => {
        wire.notify?.({method:"item/completed",params:{threadId:params.threadId,item:{type:"agentMessage",text:"НЕТ"}}});
        wire.notify?.({method:"turn/completed",params:{threadId:params.threadId,turn:{status:"completed"}}});
      });
      return {turn:{id:"turn"}};
    }
    if (method === "configRequirements/read") return {requirements:null};
    if (method === "model/list") return {data:[]};
    throw new Error(method);
  });
  const engine = new CodexEngineAdapter();
  try {
    const first = await engine.run("Йо!", {profile:"Отвечай только НЕТ."});
    const start = wire.request.mock.calls.find(([method]) => method === "thread/start")![1];
    expect(start.developerInstructions).toContain("Отвечай только НЕТ.");
    expect(wire.request.mock.calls.find(([method]) => method === "turn/start")![1].input[0].text).toBe("Йо!");
    await engine.run("Привет!", {threadId:first.threadId,profile:"Отвечай только НЕТ."});
    expect(wire.request.mock.calls.filter(([method]) => method === "thread/resume")).toHaveLength(0);
    await engine.run("Привет!", {threadId:first.threadId,profile:"Новая роль: редактор."});
    expect(wire.request.mock.calls.find(([method]) => method === "thread/resume")![1].developerInstructions).toContain("Новая роль: редактор.");
    const update = wire.request.mock.calls.find(([method]) => method === "thread/inject_items")![1];
    expect(update.items[0].role).toBe("developer");
    expect(update.items[0].content[0].text).toContain("Новая роль: редактор.");
  } finally { engine.close(); }
});

it("refreshes native MCP credentials for each group delivery without rewriting personality",async()=>{
 wire.request.mockImplementation(async(method:string,params:any)=>{
  if(method==="thread/start" || method==="thread/resume")return {thread:{id:"group"}};
  if(method==="thread/unsubscribe")return {status:"unsubscribed"};
  if(method==="turn/start"){
   queueMicrotask(()=>wire.notify?.({method:"turn/completed",params:{threadId:params.threadId,turn:{status:"completed"}}}));
   return {turn:{id:"turn"}};
  }
  if (method === "configRequirements/read") return {requirements:null};
  if (method === "model/list") return {data:[]};
  throw new Error(method);
 });
 const engine=new CodexEngineAdapter({telegramServers:{company:{url:"https://example.test/mcp",http_headers:{Authorization:"Bearer fixture"}}}});
 try{
  await engine.run("First",{profile:"Core",telegramActor:{userId:"7",chatId:"-100",messageId:"-100:1"}});
  await engine.run("Second",{threadId:"group",profile:"Core",telegramActor:{userId:"8",chatId:"-100",messageId:"-100:2"}});
  const resumed=wire.request.mock.calls.find(([method])=>method==="thread/resume")![1];
  expect(resumed.config["mcp_servers.company"].http_headers).toMatchObject({"x-hermes-user-id":"8","x-hermes-chat-id":"-100","x-hermes-message-id":"-100:2"});
  expect(wire.request.mock.calls.findIndex(([method])=>method==="thread/unsubscribe")).toBeLessThan(wire.request.mock.calls.findIndex(([method])=>method==="thread/resume"));
  expect(wire.request.mock.calls.some(([method])=>method==="thread/inject_items")).toBe(false);
  await engine.run("UI",{threadId:"group",profile:"Core"});
  expect(wire.request.mock.calls.filter(([method])=>method==="thread/resume").at(-1)![1].config["mcp_servers.company"].enabled).toBe(false);
 }finally{engine.close();}
});

it("starts a turn without access on a thread with no keyed services, apps, memories or helpers",async()=>{
 const home=mkdtempSync(join(tmpdir(),"codex-guest-")),memories=join(home,"memories"),workspace=join(home,"workspace");
 writeFileSync(join(home,"config.toml"),[
  '[mcp_servers.company]\nurl = "https://work.example/mcp"\n[mcp_servers.company.http_headers]\nAuthorization = "Bearer owner"',
  '[mcp_servers.notion]\nurl = "https://notion.example/mcp"',
  '[mcp_servers.cua_repl]\ncommand = "/Applications/Codex.app/cua"',
  '[memories]\nuse_memories = true\ngenerate_memories = true',
  `[permissions.openstrudel.filesystem]\n":minimal" = "read"\n${JSON.stringify(workspace)} = "write"\n${JSON.stringify(memories)} = "read"`,
 ].join("\n")+"\n");
 let thread=0;
 wire.request.mockImplementation(async(method:string,params:any)=>{
  if(method==="thread/start")return {thread:{id:"thread-"+(++thread)}};
  if(method==="turn/start"){queueMicrotask(()=>wire.notify?.({method:"turn/completed",params:{threadId:params.threadId,turn:{status:"completed"}}}));return {turn:{id:"turn"}};}
  if(method==="configRequirements/read")return {requirements:null};
  if(method==="model/list")return {data:[]};
  throw new Error(method);
 });
 const engine=new CodexEngineAdapter({codexHome:home,telegramServers:{wai:{url:"https://work.example/api/mcp/company/"}}});
 (engine as any).extensionManager={updating:false,pluginServers:()=>({"p@openstrudel-local":["s"]})};
 const actor={userId:"77",chatId:"-100",messageId:"-100:1"};
 try{
  await engine.run("Guest",{access:false,employees:[],telegramActor:actor,groupContext:true});
  const guest=wire.request.mock.calls.find(([method])=>method==="thread/start")![1].config;
  expect(guest).toMatchObject({"features.apps":false,"features.multi_agent":false,"memories.use_memories":false,
   "mcp_servers.company.enabled":false,"mcp_servers.notion.enabled":false,"mcp_servers.cua_repl.enabled":false,"plugins.p@openstrudel-local.mcp_servers.s.enabled":false});
  expect(guest["permissions.openstrudel.filesystem"]).toEqual({":minimal":"read",[workspace]:"write"});
  // The service that checks the sender itself stays, with the verified sender.
  expect(guest["mcp_servers.wai"]).toMatchObject({enabled:true,http_headers:{"x-hermes-user-id":"77","x-hermes-chat-id":"-100"}});
  expect(guest["mcp_servers.wai.enabled"]).toBeUndefined();
  await engine.run("Listed",{access:true,telegramActor:actor,groupContext:true});
  const listed=wire.request.mock.calls.filter(([method])=>method==="thread/start")[1]![1].config;
  expect(Object.keys(listed).filter(key=>/\.enabled$|use_memories|multi_agent/.test(key))).toEqual([]);
  expect(listed["features.apps"]).toBe(true);
  expect(listed["permissions.openstrudel.filesystem"]).toMatchObject({[memories]:"read"});
 }finally{engine.close();rmSync(home,{recursive:true,force:true});}
});

it("switches native model and speed on the same thread and explicitly clears Fast",async()=>{
  wire.request.mockImplementation(async(method:string,params:any)=>{
    if(method==="configRequirements/read")return {requirements:null};
    if(method==="model/list")return {data:[{model:"m",serviceTiers:[{id:"priority",name:"Fast"}]}]};
    if(method==="thread/start")return {thread:{id:"model-thread"}};
    if(method==="turn/start") { queueMicrotask(()=>wire.notify?.({method:"turn/completed",params:{threadId:params.threadId,turn:{status:"completed"}}})); return {turn:{id:"turn"}}; }
    throw new Error(method);
  });
  const engine=new CodexEngineAdapter();
  try{
    const first=await engine.run("First",{model:"m",serviceTier:"priority"});
    await engine.run("Second",{threadId:first.threadId,model:"m",serviceTier:"default"});
    expect(wire.request.mock.calls.filter(([m])=>m==="thread/start")).toHaveLength(1);
    expect(wire.request.mock.calls.filter(([m])=>m==="turn/start").map(([,p])=>p.serviceTier)).toEqual(["priority","default"]);
    expect(wire.request.mock.calls.filter(([m])=>m==="model/list")).toHaveLength(1);
    await expect(engine.run("Bad",{model:"m",serviceTier:"ultra"})).rejects.toThrow(/скорость/);
  }finally{engine.close();}
});
