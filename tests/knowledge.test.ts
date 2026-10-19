import { expect,it } from "vitest";
import { mkdtempSync,readFileSync,rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { Store } from "../src/store.js";
import { MessageService } from "../src/messages.js";

it("gives only the owner's root a source catalogue, keeping source text out of the prompt",async()=>{
  const root=mkdtempSync(join(tmpdir(),"knowledge-")),store=new Store(":memory:");
  const employee=store.createProfile({name:"Archive",instructions:"files"});
  const chat=store.profileConversation(employee.id);
  store.addMessage({conversationId:chat.id,channel:"api",direction:"inbound",text:"PRIVATE_SOURCE_SENTINEL"});
  const calls:any[]=[];
  const service=new MessageService(store,{async run(input,options){calls.push({input,options});return{threadId:"t",response:"ok",events:[]};}},root);
  try{
    await service.handle({channel:"api",text:"Find a source",byOwner:true});
    expect(calls[0].input).toContain("catalog.json");expect(calls[0].input).not.toContain("PRIVATE_SOURCE_SENTINEL");
    const directory=join(root,".data/owner-knowledge");
    expect(calls[0].options.readPaths).toContain(directory);
    const catalog=JSON.parse(readFileSync(join(directory,"catalog.json"),"utf8"));
    const source=catalog.sources.find((s:any)=>s.conversationId===chat.id);
    expect(readFileSync(source.history,"utf8")).toContain("PRIVATE_SOURCE_SENTINEL");
    await service.handle({channel:"api",profile:employee.id,text:"Own files",byOwner:true});
    expect(calls[1].options.readPaths).toBeUndefined();
    await service.handle({channel:"telegram",externalChatId:"42",text:"Guest",byOwner:false});
    expect(calls[2].options.readPaths).toBeUndefined();expect(calls[2].input).not.toContain("catalog.json");
  }finally{await service.close();store.close();rmSync(root,{recursive:true,force:true});}
});
