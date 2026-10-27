/** Disposable UI fixture: real HTTP and persistence, synthetic account capabilities. */
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { OpenStrudelRuntime } from '../../src/runtime.js';
import { providerModels,providerInfo } from '../../src/providers.js';
import { normalizeModels, readModelSelection, saveModelSelection, saveConversationModelSelection } from '../../src/model-settings.js';

const root = await mkdtemp(join(tmpdir(),'strudel-model-ui-'));
let unavailable = false;
let recommended = true;
const catalog = normalizeModels([
  {model:'gpt-6-astra',displayName:'GPT-6 Astra',isDefault:true,defaultReasoningEffort:'medium',supportedReasoningEfforts:[{reasoningEffort:'low'},{reasoningEffort:'medium'},{reasoningEffort:'high'}],serviceTiers:[{id:'priority',name:'Fast'}]},
  {model:'gpt-6-sol',displayName:'GPT-6 Sol',defaultReasoningEffort:'medium',supportedReasoningEfforts:[{reasoningEffort:'medium'},{reasoningEffort:'high'}],serviceTiers:[{id:'priority',name:'Fast'},{id:'ultra',name:'Ultra Fast'}]},
  {model:'gpt-6-luna',displayName:'GPT-6 Luna',serviceTiers:[]},
],null);
const runtime = new OpenStrudelRuntime({rootDirectory:root,dbPath:join(root,'home.db'),startTelegram:false,mobilePort:0,apiToken:'model-ui-owner',engine:{
  async models() { if(unavailable)throw new Error('Не удалось получить модели. Повторите попытку.');return [...catalog.map(m=>({...m,isDefault:recommended && m.isDefault})),...providerModels(providerInfo('anthropic')!)]; },
  async run(_input,options) {return {threadId:'model-ui-thread',response:`Модель: ${options?.model}. Скорость: ${options?.serviceTier}.`,events:[]};},
}});
runtime.store.setSetting('codex.auth.mode','managed');
runtime.store.setSetting('providers.anthropic.key','fixture-only');
runtime.api.home.save({...runtime.api.home.state,name:'Mac · Проверка моделей'});
runtime.account.read=async()=>({connected:true,email:'qa@example.invalid',managed:true,planType:'plus'});
Object.assign((runtime.api.mobile as any).options,{hostname:'127.0.0.1',host:'127.0.0.1',directory:join(root,'mobile')});
const profile=runtime.store.createProfile({name:'Редактор',instructions:'Пиши понятно.'});
const conversation=runtime.store.profileConversation(profile.id);
const address=await runtime.api.listen('127.0.0.1',0),url=`http://127.0.0.1:${address.port}`;
runtime.api.home.setEndpoint({url});
const controller=createServer(async(req,res)=>{
  res.setHeader('content-type','application/json');
  if(req.url==='/reset'){
    unavailable=false;recommended=true;runtime.store.deleteSetting('models.fallbacks');
    saveModelSelection(runtime.store,{provider:null,model:null,serviceTier:'default'});
    for(const agent of ['main',profile.id])saveModelSelection(runtime.store,{provider:null,model:null,serviceTier:null},agent);
    saveConversationModelSelection(runtime.store,conversation.id,{provider:null,model:null,serviceTier:null});
  }
  if(req.url==='/invite'){res.end(JSON.stringify(await runtime.api.mobile.invite(true)));return;}
  if(req.url==='/web'){res.end(JSON.stringify({url:url+'/#invite='+runtime.api.web.invite(true).key}));return;}
  // A device on an API-key model shows no speed or reasoning rows until a ChatGPT model is chosen.
  if(req.url==='/claude')saveModelSelection(runtime.store,{provider:'anthropic',model:'claude-opus-5-5',serviceTier:null});
  if(req.url?.startsWith('/unavailable'))unavailable=req.url.includes('value=1');
  if(req.url?.startsWith('/recommendation'))recommended=req.url.includes('value=1');
  res.end(JSON.stringify({profile:runtime.store.getProfile(profile.id),conversation:runtime.store.getConversation(conversation.id),fallbacks:JSON.parse(runtime.store.getSetting('models.fallbacks')||'[]'),defaults:readModelSelection(runtime.store),main:readModelSelection(runtime.store,'main')}));
});
await new Promise<void>(done=>controller.listen(0,'127.0.0.1',done));
await writeFile(resolve(process.argv[2]!),JSON.stringify({url,browser:url+'/#invite='+runtime.api.web.invite(true).key,controller:`http://127.0.0.1:${(controller.address() as any).port}`,root}),{mode:0o600});
console.log('Model settings fixture ready.');
const stop=async()=>{controller.close();await runtime.stop();await rm(root,{recursive:true,force:true});process.exit(0);};
process.once('SIGINT',stop);process.once('SIGTERM',stop);
