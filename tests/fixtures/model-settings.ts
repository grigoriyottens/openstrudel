/** Disposable UI fixture: real HTTP and persistence, synthetic account capabilities. */
import { createServer } from 'node:http';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { OpenStrudelRuntime } from '../../src/runtime.js';
import { normalizeModels, readModelSelection } from '../../src/model-settings.js';

const root = await mkdtemp(join(tmpdir(),'strudel-model-ui-'));
let unavailable = false;
const catalog = normalizeModels([
  {model:'gpt-6-astra',displayName:'GPT-6 Astra',isDefault:true,serviceTiers:[{id:'priority',name:'Fast'}]},
  {model:'gpt-6-sol',displayName:'GPT-6 Sol',serviceTiers:[{id:'priority',name:'Fast'},{id:'ultra',name:'Ultra Fast'}]},
  {model:'gpt-6-luna',displayName:'GPT-6 Luna',serviceTiers:[]},
],null);
const runtime = new OpenStrudelRuntime({rootDirectory:root,dbPath:join(root,'home.db'),startTelegram:false,mobilePort:0,apiToken:'model-ui-owner',engine:{
  async models() { if(unavailable)throw new Error('Не удалось получить модели. Повторите попытку.');return catalog; },
  async run(_input,options) {return {threadId:'model-ui-thread',response:`Модель: ${options?.model}. Скорость: ${options?.serviceTier}.`,events:[]};},
}});
runtime.api.home.save({...runtime.api.home.state,name:'Mac · Проверка моделей'});
runtime.account.read=async()=>({connected:true,email:'qa@example.invalid',managed:true,planType:'plus'});
Object.assign((runtime.api.mobile as any).options,{hostname:'127.0.0.1',host:'127.0.0.1',directory:join(root,'mobile')});
const profile=runtime.store.createProfile({name:'Редактор',instructions:'Пиши понятно.'});
const address=await runtime.api.listen('127.0.0.1',0),url=`http://127.0.0.1:${address.port}`;
runtime.api.home.setEndpoint({url});
const controller=createServer(async(req,res)=>{
  res.setHeader('content-type','application/json');
  if(req.url==='/invite'){res.end(JSON.stringify(await runtime.api.mobile.invite(true)));return;}
  if(req.url==='/web'){res.end(JSON.stringify({url:url+'/#invite='+runtime.api.web.invite(true).key}));return;}
  if(req.url?.startsWith('/unavailable'))unavailable=req.url.includes('value=1');
  res.end(JSON.stringify({profile:runtime.store.getProfile(profile.id),defaults:readModelSelection(runtime.store),main:readModelSelection(runtime.store,'main')}));
});
await new Promise<void>(done=>controller.listen(0,'127.0.0.1',done));
await writeFile(resolve(process.argv[2]!),JSON.stringify({url,browser:url+'/#invite='+runtime.api.web.invite(true).key,controller:`http://127.0.0.1:${(controller.address() as any).port}`,root}),{mode:0o600});
console.log('Model settings fixture ready.');
const stop=async()=>{controller.close();await runtime.stop();await rm(root,{recursive:true,force:true});process.exit(0);};
process.once('SIGINT',stop);process.once('SIGTERM',stop);
