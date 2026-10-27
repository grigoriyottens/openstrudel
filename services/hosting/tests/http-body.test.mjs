import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { request } from 'node:http';
import { resolve } from 'node:path';
import { Service, config } from '../src/service.mjs';
import { webhookSignature } from '../src/security.mjs';
import { createServer } from '../src/main.mjs';

mkdirSync('work/test-runs',{recursive:true});

test('a signed webhook keeps its signature when a Cyrillic character spans two network chunks',async t=>{
  const dir=mkdtempSync(resolve('work/test-runs/body-')),s=new Service(config({WAI_DATA:dir}));
  const server=createServer(s);await new Promise(r=>server.listen(0,'127.0.0.1',r));s.c.origin='http://127.0.0.1:'+server.address().port;
  t.after(()=>new Promise(r=>server.close(()=>{s.db.close();rmSync(dir,{recursive:true,force:true});r();})));
  const raw=JSON.stringify({id:'evt_split',livemode:false,type:'checkout.session.completed',data:{object:{description:'Оплата сервера · WAI'}}});
  const body=Buffer.from(raw),split=body.indexOf(Buffer.from('О'))+1;
  const reply=await new Promise((done,fail)=>{
    const r=request(s.c.origin+'/api/v1/webhooks/payment',{method:'POST',headers:{Host:new URL(s.c.origin).host,'Content-Type':'application/json','Content-Length':body.length,'Stripe-Signature':webhookSignature(raw,s.vault.webhookSecret,Math.floor(s.now()/1000))}},res=>{let text='';res.on('data',c=>text+=c);res.on('end',()=>done(text));});
    r.on('error',fail);r.write(body.subarray(0,split));setTimeout(()=>r.end(body.subarray(split)),50);
  });
  assert.doesNotMatch(reply,/Неверная подпись/);
});
