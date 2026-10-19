import { afterEach, expect, it } from "vitest";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";
import { runtimeIssues, toolProblem, toolRecovered } from "../src/operations.js";

const stores:Store[]=[];
afterEach(()=>stores.splice(0).forEach(s=>s.close()));

it("recognizes sandbox exhaustion inside native code-mode outputs without treating ordinary grep misses as outages",()=>{
  expect(toolProblem({type:"item/completed",payload:{item:{type:"functionCallOutput",name:"exec",output:[{type:"input_text",text:JSON.stringify({exit_code:1,output:"bwrap: Creating new namespace failed: Resource temporarily unavailable"})}]}}})).toBe("resources");
  expect(toolProblem({type:"item/completed",payload:{item:{type:"commandExecution",exitCode:1,aggregatedOutput:""}}})).toBeUndefined();
  expect(toolProblem({type:"item/completed",payload:{item:{type:"agentMessage",text:"Resource temporarily unavailable"}}})).toBeUndefined();
});

it("shows a failed employee at the owner's root without leaking raw tool output, then resolves on a successful turn",async()=>{
  const store=new Store(":memory:");stores.push(store);
  const root=store.primaryConversation();const profile=store.createProfile({name:"Dates",instructions:"Dates"});
  let fail=true;
  const messages=new MessageService(store,{async run(_text,options){
    if(fail)options!.onEvent!({type:"item/completed",payload:{item:{type:"commandExecution",exitCode:1,aggregatedOutput:"bwrap: Creating new namespace failed: Resource temporarily unavailable PRIVATE_SECRET"}}});
    return{threadId:"thread",response:fail?"Cannot read rules":"done",events:[]};
  }});
  try {
    await expect(messages.handle({channel:"api",profile:profile.id,text:"check",externalId:"one"})).rejects.toThrow("ресурсов");
    expect(runtimeIssues(store)).toHaveLength(1);
    const notices=store.listMessages(root.id);
    expect(notices).toHaveLength(1);expect(notices[0]!.text).toContain("Dates");expect(notices[0]!.text).not.toContain("PRIVATE_SECRET");
    fail=false;await messages.handle({channel:"api",profile:profile.id,text:"check again",externalId:"two"});
    expect(runtimeIssues(store)).toHaveLength(0);
    expect(store.listMessages(root.id).at(-1)!.text).toContain("Восстановлено");
  }finally{await messages.close();}
});

it("reports infrastructure errors thrown before the model can reply",async()=>{
  const store=new Store(":memory:");stores.push(store);
  const profile=store.createProfile({name:"Worker",instructions:"work"});
  const messages=new MessageService(store,{async run(){throw Error("Codex не смог установить этот плагин");}});
  try{await expect(messages.handle({channel:"api",profile:profile.id,text:"go"})).rejects.toThrow();expect(runtimeIssues(store)[0]?.code).toBe("tools");}
  finally{await messages.close();}
});


it("accepts an actual successful native command after recovery and does not fail the whole task",async()=>{
 const store=new Store(":memory:");stores.push(store);
 const profile=store.createProfile({name:"Recover",instructions:"work"});
 const service=new MessageService(store,{async run(_text,options){
  options!.onEvent!({type:"item/completed",payload:{item:{type:"commandExecution",exitCode:1,aggregatedOutput:"Resource temporarily unavailable"}}});
  const recovered={type:"item/completed",payload:{item:{type:"functionCallOutput",name:"exec",output:[{text:JSON.stringify({exit_code:0,output:"file read"})}]}}};
  expect(toolRecovered(recovered)).toBe(true);options!.onEvent!(recovered);
  return{threadId:"t",response:"Read successfully",events:[]};
 }});
 try{expect((await service.handle({channel:"api",profile:profile.id,text:"read"})).text).toBe("Read successfully");expect(runtimeIssues(store)).toEqual([]);}
 finally{await service.close();}
});

it("can cancel a hidden scheduled turn without reporting an intentional cancellation as an incident",async()=>{
 const store=new Store(":memory:");stores.push(store);
 const c=store.primaryConversation();let started!:()=>void;const ready=new Promise<void>(r=>started=r);
 const service=new MessageService(store,{run:async(_text,options)=>new Promise((_resolve,reject)=>{options!.signal!.addEventListener("abort",()=>reject(Error("cancelled")),{once:true});started();})});
 try{
  const job=await service.submit({channel:"api",conversationId:c.id,text:"Scheduled work",scheduled:true});
  const completion=expect(job.completion).rejects.toThrow("cancelled");await ready;
  const row=store.db.prepare("SELECT id FROM messages WHERE direction='inbound' ORDER BY rowid DESC LIMIT 1").get()!;
  store.db.prepare("UPDATE messages SET hidden=1 WHERE id=?").run(row.id);
  service.cancel(c.id,String(row.id));await completion;
  expect(runtimeIssues(store)).toEqual([]);
 }finally{await service.close();}
});


it("does not mistake a successfully read diagnostic log for a new infrastructure failure",()=>{
 expect(toolProblem({type:"item/completed",payload:{item:{type:"commandExecution",exitCode:0,aggregatedOutput:"Yesterday: Resource temporarily unavailable"}}})).toBeUndefined();
 expect(toolProblem({type:"item/completed",payload:{item:{type:"functionCallOutput",name:"exec",output:[{text:JSON.stringify({exit_code:0,output:"Yesterday: failed to fork"})}]}}})).toBeUndefined();
});
