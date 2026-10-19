import { afterEach, expect, it, vi } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";
import { TelegramAdapter } from "../src/telegram.js";
import { Scheduler } from "../src/scheduler.js";
import { employeeTools } from "../src/personality.js";
import type { TelegramToolContext } from "../src/telegram-tools.js";

const cleanup:Array<()=>Promise<void>>=[];
afterEach(async()=>{for(const close of cleanup.splice(0))await close();vi.unstubAllGlobals();});
function setup() {
  const root=mkdtempSync(join(tmpdir(),"strudel-bot-tools-"));
  const store=new Store(join(root,"test.sqlite"));
  store.linkTelegramChat({chatId:"42",title:"Owner",allowedSenders:["42"]});
  store.linkTelegramChat({chatId:"-1001",title:"Core Team",allowedSenders:["42"]});
  store.linkTelegramChat({chatId:"-1002",title:"Test group",allowedSenders:["42"]});
  store.connectTelegramGroup("-1001");store.connectTelegramGroup("-1002");
  const source=store.primaryConversation();
  const run=vi.fn(async()=>({threadId:"native-thread",response:"Готово",events:[]}));
  const engine={run};
  const messages=new MessageService(store,engine,root);
  const adapter=new TelegramAdapter("1:fixture",store,messages);messages.telegram=adapter;
  const sent:Array<{method:string;body:any}>=[];
  vi.stubGlobal("fetch",vi.fn(async(url:string,init:RequestInit)=>{
    sent.push({method:url.split("/").at(-1)!,body:init.body instanceof FormData?init.body:JSON.parse(String(init.body))});
    return Response.json({ok:true,result:{message_id:100+sent.length}});
  }));
  const context:TelegramToolContext={conversationId:source.id,messageId:"request-1",channel:"api",byOwner:true,telegram:adapter,files:messages.files,scope:messages.contextFor(source.id)};
  const tools=(overrides:Partial<TelegramToolContext>={})=>employeeTools(store,engine,messages.interactions,{...context,...overrides,profile:null});
  cleanup.push(async()=>{adapter.stop();await messages.close();store.close();rmSync(root,{recursive:true,force:true});});
  return {root,store,messages,adapter,run,sent,source,context,tools};
}

it("exposes the already connected bot in app, web and owner DM turns without an MCP login",async()=>{
  const {run,messages,store,sent}=setup();
  run.mockImplementation(async(_input,options:any)=>{
    expect(options.tools.definitions.map((t:any)=>t.name)).toContain("send_telegram_message");
    const list=await options.tools.call("list_telegram_chats",{query:"core"});
    expect(list).toEqual({chats:[{chatId:"-1001",title:"Core Team",type:"group"}]});
    const result=await options.tools.call("send_telegram_message",{chatId:list.chats[0].chatId,text:"Approved delivery",paths:[]});
    expect(result).toMatchObject({sent:true,chatId:"-1001",telegramMessageIds:[expect.any(String)]});
    return {threadId:"native-thread",response:"Отправлено",events:[]};
  });
  await messages.handle({channel:"api",text:"Send from the app",byOwner:true});
  await messages.handle({channel:"telegram",externalChatId:"42",externalId:"42:7",telegramSenderId:"42",text:"Send from DM",byOwner:true});
  expect(sent.filter(s=>s.method==="sendMessage")).toHaveLength(2);
  const target=store.getTelegramChat("-1001")!.conversationId!;
  expect(store.listMessages(target).map(m=>m.text)).toEqual(["Approved delivery","Approved delivery"]);
});

it("records only the requested content in the destination and coalesces duplicate sends",async()=>{
  const {tools,sent,store,source}=setup();
  store.addMessage({conversationId:source.id,channel:"api",direction:"inbound",text:"Private context, never forward"});
  const args={chatId:"-1001",text:"Only this text",paths:[]};
  const tool=tools();
  const [first,second]=await Promise.all([tool.call("send_telegram_message",args),tool.call("send_telegram_message",args)]) as any[];
  expect(first.sent).toBe(true);expect(second.sent).toBe(false); // first was still sending
  const repeated=await tools().call("send_telegram_message",args);
  expect(repeated).toEqual(first);expect(sent).toHaveLength(1);
  const target=store.getTelegramChat("-1001")!.conversationId!;
  expect(store.listMessages(target).map(m=>m.text)).toEqual(["Only this text"]);
  const page=store.employeeMessagePage(null,new URLSearchParams({limit:"50"}));
  expect(page.messages.find(m=>m.id===first.messageId)).toMatchObject({origin:{chatId:"-1001",title:"Core Team"},delivery:{state:"delivered"}});
});

it("sends a real GIF as an animation and preserves a downloadable copy in its destination",async()=>{
  const {tools,messages,context,sent,store}=setup();
  const workspace=messages.files.workspace(context.scope!);mkdirSync(workspace,{recursive:true});
  const path=join(workspace,"wave.gif"),bytes=Buffer.from("GIF89a-fixture");writeFileSync(path,bytes);
  const args={chatId:"-1001",text:"",paths:[path]};
  const result=await tools().call("send_telegram_message",args) as any;
  expect(result.sent).toBe(true);expect(sent).toHaveLength(1);expect(sent[0]!.method).toBe("sendAnimation");
  expect(Buffer.from(await (sent[0]!.body.get("animation") as Blob).arrayBuffer())).toEqual(bytes);
  const target=store.getTelegramChat("-1001")!.conversationId!;
  const file=store.listMessages(target)[0]!.attachments![0]!;
  expect(file).toMatchObject({conversationId:target,name:"wave.gif",mimeType:"image/gif"});
  expect(messages.files.forMessage(target,[file.id])).toHaveLength(1);
  await tools().call("send_telegram_message",args);expect(sent).toHaveLength(1);
  expect(store.db.prepare("SELECT COUNT(*) n FROM conversation_files").get()?.n).toBe(1);
});

it("keeps requested quiet delivery and link previews in the durable text and file outbox",async()=>{
  const {tools,messages,context,sent,store}=setup();
  const workspace=messages.files.workspace(context.scope!);mkdirSync(workspace,{recursive:true});
  const path=join(workspace,"night.gif");writeFileSync(path,"GIF89a-fixture");
  const args={chatId:"-1001",text:"Verified source https://example.com/news",paths:[path],silent:true,linkPreview:true};
  expect(await tools().call("send_telegram_message",args)).toMatchObject({sent:true});
  expect(sent[0]!.body).toMatchObject({disable_notification:true,link_preview_options:{is_disabled:false}});
  expect(sent[1]!.body.get("disable_notification")).toBe("true");
  const rows=store.db.prepare("SELECT payload,status FROM telegram_outbox").all();
  expect(rows).toHaveLength(2);
  expect(rows.every(row=>JSON.parse(String(row.payload)).disable_notification === true && row.status === "delivered")).toBe(true);
  // Presentation changes cannot turn a repeated request into a second send.
  expect(await tools().call("send_telegram_message",{...args,silent:false,linkPreview:false})).toMatchObject({sent:true});
  expect(sent).toHaveLength(2);
});

it("preserves ordinary delivery defaults and rejects invalid presentation options before sending",async()=>{
  const {tools,sent}=setup();
  const args={chatId:"-1001",text:"Ordinary message",paths:[]};
  await expect(tools().call("send_telegram_message",{...args,silent:"true"})).rejects.toThrow("уведомления");
  await expect(tools().call("send_telegram_message",{...args,linkPreview:1})).rejects.toThrow("предпросмотр");
  expect(sent).toEqual([]);
  expect(await tools().call("send_telegram_message",{...args,silent:null,linkPreview:null})).toMatchObject({sent:true});
  expect(sent[0]!.body.disable_notification).toBeUndefined();
  expect(sent[0]!.body.link_preview_options).toEqual({is_disabled:true});
});

it("sends documents and text through the existing outbox and reports partial failures honestly",async()=>{
  const {tools,messages,context,store}=setup();
  const workspace=messages.files.workspace(context.scope!);mkdirSync(workspace,{recursive:true});
  const path=join(workspace,"report.txt");writeFileSync(path,"Verified report");
  vi.mocked(fetch).mockImplementation(async(_url,init)=>init!.body instanceof FormData
    ? Response.json({ok:false,error_code:403,description:"Forbidden"})
    : Response.json({ok:true,result:{message_id:101}}));
  const args={chatId:"-1001",text:"Report",paths:[path]};
  const result=await tools().call("send_telegram_message",args) as any;
  expect(result).toMatchObject({sent:false,status:"partial",telegramMessageIds:["101"],error:expect.any(String)});
  await tools().call("send_telegram_message",args);expect(fetch).toHaveBeenCalledTimes(2);
  expect(store.db.prepare("SELECT status FROM telegram_outbox ORDER BY key").all().map(r=>r.status)).toEqual(["delivered","not_sent"]);
});

it("never repeats an unacknowledged send, even after a new adapter loads the persisted state",async()=>{
  const {tools,store,messages}=setup();
  vi.mocked(fetch).mockRejectedValue(new TypeError("connection lost"));
  const args={chatId:"-1001",text:"Once",paths:[]};
  expect(await tools().call("send_telegram_message",args)).toMatchObject({sent:false,status:"unknown",error:expect.stringContaining("не подтверждена")});
  const replacement=new TelegramAdapter("1:fixture",store,messages);
  expect(await tools({telegram:replacement}).call("send_telegram_message",args)).toMatchObject({sent:false});
  expect(fetch).toHaveBeenCalledTimes(1);
});

it("does not leave an unreadable file forever pending in the outbox",async()=>{
  const {messages,adapter,store,source,context,sent}=setup();
  const file=messages.files.put(source.id,context.scope!,{name:"gone.txt",contentBase64:Buffer.from("temporary").toString("base64")});
  rmSync(messages.files.get(file.id)!.path);
  await expect(adapter.sendFiles("-1001",[file],"missing-file")).rejects.toThrow();
  expect(store.db.prepare("SELECT status FROM telegram_outbox").get()?.status).toBe("not_sent");
  expect(sent).toEqual([]);
});

it("keeps an ordinary participant and an unattended schedule inside their own audience",async()=>{
  const {tools,store,sent}=setup();
  const conversationId=store.getTelegramChat("-1001")!.conversationId!;
  for (const scope of [{channel:"telegram" as const,byOwner:false,telegramSenderId:"7"},{channel:"api" as const,byOwner:false},{channel:"api" as const,byOwner:true,scheduled:true,scheduleTelegramChatId:"-1001"}]) {
    const tool=tools({...scope,conversationId});
    expect(await tool.call("list_telegram_chats",{query:null})).toEqual({chats:[{chatId:"-1001",title:"Core Team",type:"group"}]});
    await expect(tool.call("send_telegram_message",{chatId:"42",text:"Do not leak",paths:[],byOwner:true,telegramSenderId:"42"})).rejects.toThrow("недоступен");
  }
  expect(sent).toEqual([]);
});

it("delivers separate scheduled cards to the saved destination without an extra automatic post",async()=>{
  const {store,messages,run,source,sent}=setup();
  const scheduler=new Scheduler(store,messages);messages.scheduler=scheduler;
  const automatic=vi.fn(async()=>{});scheduler.deliver=automatic;
  run.mockImplementation(async(_input,options:any)=>{
    expect(await options.tools.call("list_telegram_chats",{query:null})).toEqual({chats:[{chatId:"-1002",title:"Test group",type:"group"}]});
    await expect(options.tools.call("send_telegram_message",{chatId:"-1001",text:"Another audience",paths:[]})).rejects.toThrow("недоступен");
    for (const text of ["First verified card","Second verified card"]) {
      const args={chatId:"-1002",text,paths:[]};
      expect(await options.tools.call("send_telegram_message",args)).toMatchObject({sent:true});
      expect(await options.tools.call("send_telegram_message",args)).toMatchObject({sent:true});
    }
    return {threadId:"scheduled-cards",response:"NO_REPLY",events:[]};
  });
  scheduler.save({conversationId:source.id,name:"Cards",prompt:"Send each card separately",cron:"0 7 * * *",timezone:"Europe/Moscow",delivery:"telegram",telegramChatId:"-1002"},new Date("2026-10-15T10:00:00Z"));
  await scheduler.tick(new Date("2026-10-16T04:00:01Z"));await scheduler.idle();
  expect(scheduler.runs(source.id)[0]).toMatchObject({status:"quiet"});
  expect(automatic).not.toHaveBeenCalled();
  expect(sent).toHaveLength(2);
  expect(sent.map(s=>s.body.chat_id)).toEqual(["-1002","-1002"]);
  const target=store.getTelegramChat("-1002")!.conversationId!;
  expect(store.listMessages(target).map(m=>m.text)).toEqual(["First verified card","Second verified card"]);
});

it("does not let an app-only schedule send to a bound Telegram chat",async()=>{
  const {store,messages,run,sent}=setup();
  const conversationId=store.getTelegramChat("-1001")!.conversationId!;
  const scheduler=new Scheduler(store,messages);messages.scheduler=scheduler;
  run.mockImplementation(async(_input,options:any)=>{
    expect(await options.tools.call("list_telegram_chats",{query:null})).toEqual({chats:[]});
    await expect(options.tools.call("send_telegram_message",{chatId:"-1001",text:"Keep in app",paths:[]})).rejects.toThrow("недоступен");
    return {threadId:"app-edition",response:"App only",events:[]};
  });
  scheduler.save({conversationId,name:"Private review",prompt:"Review only",cron:"0 7 * * *",timezone:"Europe/Moscow",delivery:"app"},new Date("2026-10-15T10:00:00Z"));
  await scheduler.tick(new Date("2026-10-16T04:00:01Z"));await scheduler.idle();
  expect(scheduler.runs(conversationId)[0]).toMatchObject({status:"completed"});
  expect(sent).toEqual([]);
});

it("rechecks a scheduled destination's availability and cannot grant itself another audience",async()=>{
  const {tools,store,sent}=setup();
  const tool=tools({scheduled:true,scheduleTelegramChatId:"-1002"});
  store.setSetting("telegram.paused.-1002","true");
  expect(await tool.call("list_telegram_chats",{query:null})).toEqual({chats:[]});
  await expect(tool.call("send_telegram_message",{chatId:"-1001",text:"No",paths:[],scheduleTelegramChatId:"-1001"})).rejects.toThrow("недоступен");
  await expect(tool.call("send_telegram_message",{chatId:"-1002",text:"No",paths:[]})).rejects.toThrow("недоступен");
  expect(sent).toEqual([]);
});

it("lets a verified owner explicitly dispatch from a group while retaining group-scoped tools",async()=>{
  const {tools,store}=setup();
  const conversationId=store.getTelegramChat("-1001")!.conversationId!;
  const tool=tools({conversationId,byOwner:false,channel:"telegram",telegramSenderId:"42",scope:"group-test"});
  expect(await tool.call("send_telegram_message",{chatId:"-1002",text:"Requested by owner",paths:[]})).toMatchObject({sent:true});
  await expect(tool.call("update_employee",{name:"Other",instructions:"Change globally"})).rejects.toThrow("личном чате");
});

it("rechecks membership, pause and owner access at tool time",async()=>{
  const {tools,store,sent}=setup();
  const tool=tools({byOwner:false,channel:"telegram",telegramSenderId:"42"});
  store.setSetting("telegram.paused.-1001","true");
  await expect(tool.call("send_telegram_message",{chatId:"-1001",text:"No",paths:[]})).rejects.toThrow("недоступен");
  store.db.prepare("DELETE FROM telegram_chats WHERE chat_id='-1002'").run();
  await expect(tool.call("send_telegram_message",{chatId:"-1002",text:"No",paths:[]})).rejects.toThrow("недоступен");
  store.db.prepare("DELETE FROM telegram_chats WHERE chat_id='42'").run();
  expect(await tool.call("list_telegram_chats",{query:null})).toEqual({chats:[]});
  expect(sent).toEqual([]);
});

it("rejects outside files, symlinks and empty sends before contacting Telegram",async()=>{
  const {tools,messages,context,root,sent}=setup();
  const workspace=messages.files.workspace(context.scope!);mkdirSync(workspace,{recursive:true});
  const secret=join(root,"secret.txt");writeFileSync(secret,"private");symlinkSync(secret,join(workspace,"link.txt"));
  for (const paths of [[secret],[join(workspace,"link.txt")]]) await expect(tools().call("send_telegram_message",{chatId:"-1001",text:"",paths})).rejects.toThrow("рабочей области");
  await expect(tools().call("send_telegram_message",{chatId:"-1001",text:" ",paths:[]})).rejects.toThrow("текст или файл");
  expect(sent).toEqual([]);
});

it("identifies a disconnected device bot without asking for a duplicate MCP integration",async()=>{
  const {tools,adapter}=setup();adapter.disconnect();
  await expect(tools().call("list_telegram_chats",{query:null})).rejects.toThrow("Дополнительный сервис Telegram сотруднику не нужен");
});
