import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { readFile } from "node:fs/promises";
import type { MobileAccess } from "./mobile.js";

/** Only issues invitations. The Home API remains private behind pinned TLS. */
export function createSetupServer(mobile: Pick<MobileAccess, "invite">, code: string) {
  if (!/^[a-f0-9]{64}$/.test(code)) throw new Error("OPENSTRUDEL_SETUP_CODE must contain 64 random hexadecimal characters");
  const credential = Buffer.from(code);
  return createServer(async (req, res) => {
    res.setHeader("cache-control", "no-store");
    res.setHeader("referrer-policy", "no-referrer");
    res.setHeader("x-content-type-options", "nosniff");
    res.setHeader("content-security-policy", "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");
    if (req.method === "GET" && req.url === "/") {
      res.setHeader("content-type", "text/html; charset=utf-8"); res.end(page); return;
    }
    if (req.method === "GET" && req.url === "/setup.js") {
      res.setHeader("content-type", "text/javascript; charset=utf-8"); res.end(script); return;
    }
    if (req.method === "GET" && ["/localization.js", "/localizations.json"].includes(req.url ?? "")) {
      try {
        const body = await readFile(new URL("../public" + req.url, import.meta.url));
        res.setHeader("content-type", req.url === "/localization.js" ? "text/javascript; charset=utf-8" : "application/json; charset=utf-8");
        res.end(body);
      } catch { res.writeHead(503).end(); }
      return;
    }
    res.setHeader("content-type", "application/json; charset=utf-8");
    if (req.method === "GET" && req.url === "/healthz") { res.end('{"ok":true}'); return; }
    if (req.method !== "POST" || req.url !== "/pairing") { res.writeHead(404).end('{}'); return; }
    if (req.headers.origin && !["https://" + req.headers.host, "http://" + req.headers.host].includes(req.headers.origin)) {
      res.writeHead(403).end('{}'); return;
    }
    const given = Buffer.from((req.headers.authorization ?? "").replace(/^Bearer /, ""));
    if (given.length !== credential.length || !timingSafeEqual(given, credential)) {
      res.writeHead(401).end(JSON.stringify({ error: "Open your private setup link or enter the setup code." })); return;
    }
    try { res.writeHead(201).end(JSON.stringify(await mobile.invite(true))); }
    catch { res.writeHead(503).end(JSON.stringify({ error: "Your server is starting. Try again in a few seconds." })); }
  });
}

const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title data-i18n="Connect OpenStrudel">Connect OpenStrudel</title>
<style>:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:light-dark(#f6f5f3,#141417);color:light-dark(#202023,#f5f5f7)}*{box-sizing:border-box}body{margin:0;min-height:100svh;display:grid;place-items:center;padding:28px}main{width:min(100%,420px)}.brand{font-size:15px;letter-spacing:-.03em;margin-bottom:44px}h1{font-family:ui-serif,Georgia,serif;font-size:44px;font-weight:500;letter-spacing:-.04em;line-height:1.05;margin:0 0 22px}p{line-height:1.55;color:light-dark(#696970,#b2b2bc)}button,.primary,input{font:inherit;border:0;border-radius:16px;padding:16px;width:100%;margin-top:12px}.primary,button{background:light-dark(#262632,#f1f1f5);color:light-dark(#fff,#16161c);cursor:pointer;display:block;text-align:center;text-decoration:none}input{background:light-dark(#fff,#29292e);border:1px solid light-dark(#d6d6dc,#414149)}button:disabled{opacity:.45;cursor:wait}.quiet{background:none;color:inherit;border:1px solid light-dark(#d6d6dc,#414149)}small{font-size:13px}a{color:inherit}[hidden]{display:none!important}:focus-visible{outline:3px solid #9090ef;outline-offset:3px}</style>
<style>.brand{display:flex;align-items:center;justify-content:space-between;gap:20px}select{font:inherit;font-size:13px;color:inherit;background:none;border:1px solid light-dark(#d6d6dc,#414149);border-radius:10px;padding:8px;max-width:150px}h1{font-size:clamp(34px,9vw,44px)}input{direction:ltr;text-align:start}</style>
<main><div class="brand"><span>OpenStrudel</span><select id="language" aria-label="Language" data-i18n-aria-label="Language"></select></div><h1 data-i18n="Meet your assistants.">Meet your assistants.</h1><p data-i18n="Connect the app to your server. Your assistants and chats will appear in the app.">Connect the app to your server. Your assistants and chats will appear in the app.</p>
<div id="entry"><label for="code" data-i18n="Setup code">Setup code</label><input id="code" type="password" autocomplete="off" spellcheck="false" placeholder="From your server settings" data-i18n-placeholder="From your server settings"><button id="connect" data-i18n="Create connection link">Create connection link</button></div>
<div id="result" hidden><a class="primary" id="open" data-i18n="Open OpenStrudel">Open OpenStrudel</a><button class="quiet" id="copy">Copy connection link</button><p id="expiry"></p><button class="quiet" id="refresh" data-i18n="New connection link">New connection link</button></div>
<p id="status" role="status" aria-live="polite"></p><p><small><a href="https://waiwai.is/openstrudel" data-i18n="Download OpenStrudel">Download OpenStrudel</a><br><span data-i18n="This private link gives access to your chats. Keep it to yourself.">This private link gives access to your chats. Keep it to yourself.</span></small></p></main><script src="localization.js"></script><script src="setup.js"></script></html>`;

const script = `const $=id=>document.getElementById(id);let code=location.hash.slice(1),invite=null,status='',copied=false;
history.replaceState(null,'',location.pathname);if(code){$('code').value=code;$('entry').hidden=true;}
function render(){applyInterfaceLanguage();$('language').value=i18n.language;$('status').textContent=t(status);$('copy').textContent=t(copied?'Скопировано':'Copy connection link');tick();}
async function connect(){code=$('code').value.trim();$('connect').disabled=true;$('refresh').disabled=true;status='Preparing your connection…';render();
try{const r=await fetch('pairing',{method:'POST',headers:{Authorization:'Bearer '+code},signal:AbortSignal.timeout(20000)});const data=await r.json();if(!r.ok)throw new Error(data.error||'Could not connect. Try again.');invite=data;copied=false;$('open').href=data.url;$('open').hidden=false;$('copy').disabled=false;$('entry').hidden=true;$('result').hidden=false;status='';}
catch(e){status=['Open your private setup link or enter the setup code.','Your server is starting. Try again in a few seconds.'].includes(e.message)?e.message:'Could not connect. Try again.';$('entry').hidden=false;}finally{$('connect').disabled=false;$('refresh').disabled=false;render();}}
function tick(){if(!invite)return;const seconds=Math.max(0,Math.ceil((new Date(invite.expiresAt)-Date.now())/1000));$('expiry').textContent=t(seconds?'Ссылка действует сутки и подключает одно устройство.':'This link has expired. Create a new one.');if(!seconds){$('open').hidden=true;$('copy').disabled=true;}}
for(const [code,name] of StrudelLocale.languages){const option=document.createElement('option');option.value=code;option.textContent=name;$('language').append(option);}
$('language').onchange=()=>{setInterfaceLanguage($('language').value);render();};
$('connect').onclick=connect;$('refresh').onclick=connect;$('copy').onclick=async()=>{try{await navigator.clipboard.writeText(invite.url);copied=true;}catch{status='Open this page on the device with OpenStrudel, then choose Open OpenStrudel.';}render();};
addEventListener('hashchange',()=>{if(!location.hash.slice(1))return;code=location.hash.slice(1);history.replaceState(null,'',location.pathname);$('code').value=code;connect();});
setInterval(tick,1000);languageReady.catch(()=>{}).then(()=>{render();if(code)connect();});`;
