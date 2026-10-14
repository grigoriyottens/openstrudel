import { expect, it, vi } from 'vitest';
import { Store } from '../src/store.js';
import { MessageService } from '../src/messages.js';
import { normalizeModels, readModelSelection, saveModelSelection, resolveModelSelection, validateModelSelection, recommendedModel, parseModelSelection } from '../src/model-settings.js';
const catalog = normalizeModels([
 {model:'m1',displayName:'Model One',isDefault:true,serviceTiers:[{id:'priority',name:'Fast',description:'Increased usage'}]},
 {model:'m2',displayName:'Model Two',serviceTiers:[{id:'priority',name:'Fast'},{id:'ultra',name:'Ultra Fast'}]},
 {model:'hidden',hidden:true},
],null);
it('follows the account recommendation and falls back to GPT-6.1 Sol with Medium reasoning',()=>{
 const recommended=normalizeModels([{model:'preferred',isDefault:true,defaultReasoningEffort:'high'}],null);
 expect(recommendedModel(recommended)).toMatchObject({id:'preferred',defaultReasoningEffort:'high'});
 const unmarked=normalizeModels([{model:'other'},{model:'gpt-6.1-sol',defaultReasoningEffort:'low'}],null);
 expect(recommendedModel(unmarked)).toMatchObject({id:'gpt-6.1-sol',defaultReasoningEffort:'medium',isDefault:false});
 expect(recommendedModel([])).toMatchObject({id:'gpt-6.1-sol',defaultReasoningEffort:'medium'});
 const store=new Store(':memory:');
 try {
  expect(readModelSelection(store)).toEqual({provider:null,model:null,serviceTier:'default'});
  expect(resolveModelSelection(store,undefined,recommended)).toEqual({provider:'chatgpt',model:'preferred',serviceTier:'default'});
  saveModelSelection(store,{provider:'chatgpt',model:'chosen',serviceTier:'default'});
  expect(resolveModelSelection(store,undefined,recommended).model).toBe('chosen');
  expect(parseModelSelection({model:null,serviceTier:'default'},false)).toEqual({provider:null,model:null,serviceTier:'default'});
  saveModelSelection(store,{provider:null,model:null,serviceTier:'default'});
  expect(resolveModelSelection(store,undefined,[]).model).toBe('gpt-6.1-sol');
 } finally {store.close();}
});
it('uses the live catalog and managed speed restrictions, without inventing Ultra Fast',()=>{
 expect(catalog.map(m=>m.id)).toEqual(['m1','m2']);
 expect(catalog[0].speeds.map(s=>s.id)).toEqual(['default','priority']);
 expect(normalizeModels([{model:'m',serviceTiers:[{id:'priority',name:'Fast'},{id:'ultra',name:'Ultra Fast'}]}],{featureRequirements:{fast_mode:false}})[0].speeds.map(s=>s.id)).toEqual(['default']);
 expect(()=>validateModelSelection({model:'m1',serviceTier:'ultra'},catalog)).toThrow('скорость');
 expect(()=>validateModelSelection({model:'missing',serviceTier:'default'},catalog)).toThrow('модель');
});
it('reads a stored model without a provider as ChatGPT and resolves automatic to who is connected',()=>{
 const store=new Store(':memory:');
 try {
 store.setSetting('models.defaults',JSON.stringify({model:'gpt-6-sol',serviceTier:'priority'}));
 const legacy=store.createProfile({name:'Legacy',model:'gpt-6-luna'});
 expect(readModelSelection(store)).toEqual({provider:'chatgpt',model:'gpt-6-sol',serviceTier:'priority'});
 expect(readModelSelection(store,legacy.id)).toEqual({provider:'chatgpt',model:'gpt-6-luna',serviceTier:'default'});
 expect(resolveModelSelection(store,'main')).toEqual({provider:'chatgpt',model:'gpt-6-sol',serviceTier:'priority'});
 saveModelSelection(store,{provider:null,model:null,serviceTier:'priority'});
 expect(resolveModelSelection(store,'main')).toEqual({provider:'chatgpt',model:null,serviceTier:'priority'});
 store.setSetting('providers.kimi.key','kimi-key');store.setSetting('providers.xai.key','xai-key');
 expect(resolveModelSelection(store,'main')).toEqual({provider:'xai',model:'grok-4.7',serviceTier:'default'});
 store.setSetting('codex.auth.mode','managed');
 expect(resolveModelSelection(store,'main',catalog)).toEqual({provider:'chatgpt',model:'m1',serviceTier:'priority'});
 saveModelSelection(store,{provider:'kimi',model:'kimi-k2.7-code',serviceTier:'default'},legacy.id);
 expect(store.getProfile(legacy.id)).toMatchObject({provider:'kimi',model:'kimi-k2.7-code'});
 expect(resolveModelSelection(store,legacy.id)).toEqual({provider:'kimi',model:'kimi-k2.7-code',serviceTier:'default'});
 expect(parseModelSelection({provider:'xai',model:'grok-4.5',serviceTier:'default'},true)).toEqual({provider:'xai',model:'grok-4.5',serviceTier:'default'});
 expect(parseModelSelection({model:'gpt-6-sol',serviceTier:'default'},true)).toEqual({provider:'chatgpt',model:'gpt-6-sol',serviceTier:'default'});
 expect(parseModelSelection({provider:null,model:null,serviceTier:null},true)).toEqual({provider:null,model:null,serviceTier:null});
 expect(()=>parseModelSelection({provider:'elsewhere',model:'x',serviceTier:'default'},true)).toThrow();
 expect(()=>parseModelSelection({provider:'xai',model:null,serviceTier:'default'},false)).toThrow();
 }finally{store.close();}
});
it('inherits device defaults, keeps employee overrides and restores inheritance',()=>{
 const store=new Store(':memory:');
 try {
 const employee=store.createProfile({name:'Editor'});
 saveModelSelection(store,{provider:'chatgpt',model:'m1',serviceTier:'priority'});
 expect(resolveModelSelection(store,employee.id)).toEqual({provider:'chatgpt',model:'m1',serviceTier:'priority'});
 saveModelSelection(store,{provider:'chatgpt',model:'m2',serviceTier:'ultra'},employee.id);
 saveModelSelection(store,{provider:'chatgpt',model:'m1',serviceTier:'default'});
 expect(resolveModelSelection(store,employee.id)).toEqual({provider:'chatgpt',model:'m2',serviceTier:'ultra'});
 expect(store.getProfile(employee.id)).toMatchObject({model:'m2',serviceTier:'ultra'});
 saveModelSelection(store,{provider:null,model:null,serviceTier:null},employee.id);
 expect(readModelSelection(store,employee.id)).toEqual({provider:null,model:null,serviceTier:null});
 expect(resolveModelSelection(store,employee.id)).toEqual({provider:'chatgpt',model:'m1',serviceTier:'default'});
 expect(()=>saveModelSelection(store,{provider:'chatgpt',model:'m2',serviceTier:'default'},'missing')).toThrow();
 }finally{store.close();}
});
it('applies the choice to the next queued turn, preserves the thread and covers Telegram',async()=>{
 const store=new Store(':memory:');let finish!:()=>void;const seen:any[]=[];
 const messages=new MessageService(store,{run:async(_input,options)=>{seen.push(options);if(seen.length===1)await new Promise<void>(r=>finish=r);return {threadId:'same-thread',response:'OK',events:[]};}});
 try {
 saveModelSelection(store,{provider:'chatgpt',model:'m1',serviceTier:'priority'});
 const first=await messages.submit({channel:'api',text:'First',externalChatId:'home'});
 await vi.waitFor(()=>expect(seen).toHaveLength(1));
 saveModelSelection(store,{provider:'chatgpt',model:'m2',serviceTier:'default'});
 const next=await messages.submit({channel:'api',text:'Next',externalChatId:'home'});
 finish();await Promise.all([first.completion,next.completion]);
 expect(seen[0]).toMatchObject({model:'m1',serviceTier:'priority'});
 expect(seen[1]).toMatchObject({model:'m2',serviceTier:'default',threadId:'same-thread'});
 await messages.handle({channel:'telegram',text:'Hi',externalChatId:'42',telegramSenderId:'42',externalId:'42:1'});
 expect(seen[2]).toMatchObject({model:'m2',serviceTier:'default'});
 }finally{store.close();}
});

it('delegated employees use their device defaults even when the main assistant has an override',async()=>{
 const store=new Store(':memory:');let seen:any;
 const messages=new MessageService(store,{run:async(_input,options)=>{seen=options;return {threadId:'t',response:'OK',events:[]};}});
 try {
 const employee=store.createProfile({name:'Editor'});
 saveModelSelection(store,{provider:'chatgpt',model:'m1',serviceTier:'priority'});
 saveModelSelection(store,{provider:'chatgpt',model:'m2',serviceTier:'default'},'main');
 await messages.handle({channel:'api',text:'Ask Editor',externalChatId:'home'});
 expect(seen).toMatchObject({model:'m2',serviceTier:'default'});
 expect(seen.employees.find((p:any)=>p.id===employee.id)).toMatchObject({model:'m1',serviceTier:'priority'});
 }finally{store.close();}
});

it('serves account capabilities, validates writes and denies members before changing preferences',async()=>{
 const {OpenStrudelRuntime}=await import('../src/runtime.js');
 const runtime=new OpenStrudelRuntime({dbPath:':memory:',startTelegram:false,apiToken:'owner',engine:{models:async()=>catalog,run:async()=>({threadId:'t',response:'OK',events:[]})}});
 const addr=await runtime.api.listen('127.0.0.1',0);
 const call=(path:string,method='GET',body?:any,headers:any={authorization:'Bearer owner'})=>fetch(`http://127.0.0.1:${addr.port}${path}`,{method,headers:{'content-type':'application/json',...headers},body:body===undefined?undefined:JSON.stringify(body)});
 try{
 const employee=runtime.store.createProfile({name:'QA'});
 const defaults='/v1/settings/models',override=defaults+'?agentId='+employee.id;
 const initial=await (await call(defaults)).json();
 expect(initial.models).toEqual(catalog);
 expect(initial.selection).toEqual({provider:null,model:null,serviceTier:'default'});
 expect(initial.effective).toEqual({provider:'chatgpt',model:'m1',serviceTier:'default'});
 expect((await call(defaults,'POST',{model:'m1',serviceTier:'ultra'})).status).toBe(409);
 expect((await call(defaults,'POST',{model:'m1',serviceTier:'priority'})).status).toBe(200);
 expect((await (await call(override)).json()).effective).toEqual({provider:'chatgpt',model:'m1',serviceTier:'priority'});
 expect((await call(override,'POST',{model:'m2',serviceTier:'ultra'})).status).toBe(200);
 const session=await call('/auth/session','POST',{key:runtime.api.web.invite(false).key});const {csrf}=await session.json();
 const headers={cookie:session.headers.get('set-cookie')!.split(';')[0],'x-openstrudel-csrf':csrf};
 expect((await (await call(override,'GET',undefined,headers)).json()).canManage).toBe(false);
 expect((await call(override,'POST',{model:null,serviceTier:null},headers)).status).toBe(403);
 expect((await call(override,'POST',{model:null,serviceTier:null})).status).toBe(200);
 expect((await (await call(override)).json()).effective).toEqual({provider:'chatgpt',model:'m1',serviceTier:'priority'});
 expect((await call(defaults+'?agentId=missing')).status).toBe(404);
 expect((await call(defaults,'POST',{model:null,serviceTier:'priority'})).status).toBe(200);
 expect((await (await call(override)).json()).effective).toEqual({provider:'chatgpt',model:'m1',serviceTier:'priority'});
 expect((await call(defaults,'POST',{model:null,serviceTier:'ultra'})).status).toBe(409);
 }finally{await runtime.stop();}
});
