import { expect, it } from 'vitest';
import { Store } from '../src/store.js';
import { ownerTimezone, saveOwnerTimezone } from '../src/timezone.js';
import { MessageService } from '../src/messages.js';
import { OpenStrudelRuntime } from '../src/runtime.js';

it('keeps the first owner timezone when another device opens and rejects unknown zones',async()=>{
 const store=new Store(':memory:');let seen:any;
 try {
  expect(saveOwnerTimezone(store,'Europe/Moscow',true)).toBe('Europe/Moscow');
  expect(saveOwnerTimezone(store,'America/New_York',true)).toBe('Europe/Moscow');
  expect(()=>saveOwnerTimezone(store,'Tomorrow/Here')).toThrow('пояс');
  const messages=new MessageService(store,{run:async(_input,o)=>{seen=o;return{threadId:'t',response:'ok',events:[]};}});
  await messages.handle({channel:'api',externalChatId:'home',text:'Remind me tomorrow'});
  expect(seen.profile).toContain('Owner timezone: Europe/Moscow');
  expect(saveOwnerTimezone(store,'Europe/Berlin')).toBe('Europe/Berlin');
  expect(ownerTimezone(store)).toBe('Europe/Berlin');
  await messages.close();
 }finally{store.close();}
});

it('initializes remotely from an owner, never from a colleague, without rewriting saved schedules',async()=>{
 const runtime=new OpenStrudelRuntime({dbPath:':memory:',startTelegram:false,apiToken:'owner'});
 const addr=await runtime.api.listen('127.0.0.1',0);
 const call=(path:string,body?:any,headers:any={authorization:'Bearer owner'})=>fetch(`http://127.0.0.1:${addr.port}${path}`,{method:body?'POST':'GET',headers:{'content-type':'application/json',...headers},body:body?JSON.stringify(body):undefined});
 try {
  expect(await (await call('/v1/mobile')).json()).toMatchObject({timezoneVersion:1,timezone:null});
  const login=await call('/auth/session',{key:runtime.api.web.invite(false).key});const {csrf}=await login.json();
  const member={cookie:login.headers.get('set-cookie')!.split(';')[0],'x-openstrudel-csrf':csrf};
  expect((await call('/v1/settings/timezone',{timezone:'Europe/Moscow',initialize:true},member)).status).toBe(403);
  expect((await call('/v1/settings/timezone',{timezone:'Europe/Moscow',initialize:true})).status).toBe(200);
  expect(await (await call('/v1/settings/timezone',{timezone:'UTC',initialize:true})).json()).toEqual({timezone:'Europe/Moscow',configured:true});
  expect((await call('/v1/settings/timezone',{timezone:'Mars'})).status).toBe(400);
 }finally{await runtime.stop();}
});
