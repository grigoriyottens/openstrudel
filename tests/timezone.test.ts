import { expect, it, vi } from 'vitest';
import { Store } from '../src/store.js';
import { ownerTimezone, saveOwnerTimezone } from '../src/timezone.js';
import { MessageService } from '../src/messages.js';
import { OpenStrudelRuntime } from '../src/runtime.js';
import { Scheduler } from '../src/scheduler.js';

it('never presents the server clock as the owner timezone or silently schedules in UTC',async()=>{
 const store=new Store(':memory:');let seen:any;
 const messages=new MessageService(store,{run:async(_input,o)=>{seen=o;return{threadId:'t',response:'ok',events:[]};}});
 messages.scheduler=new Scheduler(store,messages);
 try {
  expect(ownerTimezone(store)).toBeNull();
  // The paired owner's private chat, as the Telegram adapter delivers it.
  store.linkTelegramChat({chatId:'42',title:'Owner',allowedSenders:['42']});
  await messages.handle({channel:'telegram',externalChatId:'42',telegramSenderId:'42',text:'Remind me at 16:20'});
  expect(seen.profile).toContain('Owner timezone is not configured');
  expect(seen.profile).not.toContain('Owner timezone: UTC');
  expect(await seen.tools.call('list_schedules',{})).toMatchObject({timezone:null,localTime:null});
  await expect(seen.tools.call('save_schedule',{name:'Reminder',prompt:'Remind me',cron:'20 16 * * *',timezone:''})).rejects.toThrow('пояс');
  expect(store.db.prepare('SELECT count(*) n FROM schedules').get()?.n).toBe(0);
  // An explicit timezone still works for a Telegram-only owner.
  expect(await seen.tools.call('save_schedule',{name:'Reminder',prompt:'Remind me',cron:'20 16 * * *',timezone:'Asia/Tokyo'})).toMatchObject({timezone:'Asia/Tokyo'});
 }finally{await messages.close();store.close();}
});

it('uses owner wall time for new schedules, preserves edits and honors explicit UTC',async()=>{
 vi.useFakeTimers();vi.setSystemTime(new Date('2026-10-16T14:30:00Z'));
 const store=new Store(':memory:');let seen:any;
 const messages=new MessageService(store,{run:async(_input,o)=>{seen=o;return{threadId:'t',response:'ok',events:[]};}});
 messages.scheduler=new Scheduler(store,messages);
 try {
  saveOwnerTimezone(store,'Europe/Moscow');
  await messages.handle({channel:'api',externalChatId:'home',text:'At 16:20 except Saturday'});
  const args={name:'Reminder',prompt:'Remind me',cron:'20 16 * * 0-5',timezone:''};
  const saved=await seen.tools.call('save_schedule',args);
  expect(saved).toMatchObject({timezone:'Europe/Moscow',nextRunAt:'2026-10-18T13:20:00.000Z',nextRunLocal:'Sunday, 18/10/2026, 16:20 (Europe/Moscow)'});
  expect(await seen.tools.call('list_schedules',{})).toMatchObject({currentTime:'2026-10-16T14:30:00.000Z',localTime:'Friday, 16/10/2026, 17:30 (Europe/Moscow)'});
  saveOwnerTimezone(store,'Europe/Berlin');
  expect(await seen.tools.call('save_schedule',{...args,id:saved.id,name:'Renamed'})).toMatchObject({timezone:'Europe/Moscow',nextRunAt:saved.nextRunAt});
  expect(await seen.tools.call('save_schedule',{...args,timezone:'UTC'})).toMatchObject({timezone:'UTC',nextRunAt:'2026-10-16T16:20:00.000Z'});
 }finally{await messages.close();store.close();vi.useRealTimers();}
});

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
  expect(await (await call('/v1/settings/timezone')).json()).toEqual({timezone:null,configured:false});
  const login=await call('/auth/session',{key:runtime.api.web.invite(false).key});const {csrf}=await login.json();
  const member={cookie:login.headers.get('set-cookie')!.split(';')[0],'x-openstrudel-csrf':csrf};
  expect((await call('/v1/settings/timezone',{timezone:'Europe/Moscow',initialize:true},member)).status).toBe(403);
  expect((await call('/v1/settings/timezone',{timezone:'Europe/Moscow',initialize:true})).status).toBe(200);
  expect(await (await call('/v1/settings/timezone',{timezone:'UTC',initialize:true})).json()).toEqual({timezone:'Europe/Moscow',configured:true});
  expect((await call('/v1/settings/timezone',{timezone:'Mars'})).status).toBe(400);
 }finally{await runtime.stop();}
});
