import {expect,it} from 'vitest';
import {Store} from '../src/store.js';
import {Scheduler} from '../src/scheduler.js';
import {MessageService} from '../src/messages.js';
import {telegramTools} from '../src/telegram-tools.js';

it('keeps long owner instructions and scheduled prompts intact',()=>{
 const store=new Store(':memory:');
 const text='Full instructions. '.repeat(1500);
 try{
  const p=store.createProfile({name:'Research',instructions:text});
  expect(p.instructions).toBe(text.trim());
  expect(store.updateProfile(p.id,{name:p.name,instructions:text+'Updated'}).instructions).toBe(text+'Updated');
  const messages=new MessageService(store,{run:async()=>({threadId:'t',response:'ok',events:[]})});
  const scheduler=new Scheduler(store,messages);
  const schedule=scheduler.save({conversationId:store.primaryConversation().id,name:'Research',prompt:text,cron:'0 9 * * *',timezone:'Europe/Moscow'});
  expect(schedule.prompt).toBe(text.trim());
 }finally{store.close();}
});

it('sends a long authorized Telegram response through the existing chunked transport',async()=>{
 const store=new Store(':memory:');
 try{
  store.linkTelegramChat({chatId:'42',title:'Owner',allowedSenders:['42']});
  const text='A'.repeat(40_000);let received='';
  const tools=telegramTools(store,{conversationId:store.primaryConversation().id,messageId:'m',channel:'api',byOwner:true,telegram:{enabled:()=>true,sendToChat:async(i:any)=>{received=i.text;return{sent:true};}} as any});
  expect(await tools.call('send_telegram_message',{chatId:'42',text,paths:[]})).toMatchObject({sent:true});
  expect(received).toBe(text);
 }finally{store.close();}
});
