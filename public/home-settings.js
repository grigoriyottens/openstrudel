function element(tag, text, className) { const e = document.createElement(tag); if (text) e.textContent = text; if (className) e.className = className; return e; }
/* A modal page: title, content, then a bottom bar with Cancel first and one main action last.
   close: 'done' (default), 'cancel', or false when the page owns its buttons or must not be dismissed.
   back: the page this one was opened from ({label, open, row, back}); it leads with a way back to it.
   A locked page is the whole screen. */
function modalPage(title, description, { close: closeKind = 'done', locked = false, back = state.back } = {}) {
  const box = element('div', '', 'page');
  if (back && !locked) { const button = element('button', '', 'back'), label = element('span', back.label); label.dir = 'auto'; button.type = 'button'; button.append(icon('back', true), label); button.onclick = () => void goBack(back); box.append(button); }
  box.append(element('h2', title)); if (description) box.append(element('p', description, 'description'));
  if (locked) box.dataset.locked = 'true';
  document.body.classList.toggle('locked', locked);
  const error = element('p'); error.setAttribute('role','alert'); box.append(error);
  const content = element('div', '', 'page-content'); box.append(content);
  const actions = element('div', '', 'modal-actions'); box.append(actions);
  let close = null;
  if (closeKind) { close = element('button', closeKind === 'cancel' ? t("Отмена") : t("Готово"), 'secondary'); close.type = 'button'; close.onclick = closeModal; actions.append(close); }
  const page = { box, content, actions, error, close, report: e => { error.textContent = i18n.error(e.message); } };
  arrange(page);
  showModal(box); (close || $('modal-content')).focus();
  return page;
}
/* One step back: the earlier page opens with its own way back, and focus returns to the row the person came from. */
function goBack(back) {
  state.back = back.back || null;
  const opened = back.open();
  const row = [...$('modal-content').querySelectorAll('.row')].find(node => node.querySelector('.row-title')?.textContent === back.row);
  row?.focus();
  return opened;
}
/* Keeps the bar in order: Cancel or Done, secondary actions, then the one main action. A page with no
   main action ends with Done as its default button. */
function arrange(page) {
  const buttons = [...page.actions.children];
  const main = buttons.find(button => button.dataset.main === 'true');
  const others = buttons.filter(button => button !== page.close && button !== main);
  const order = page.close ? (main ? [page.close, ...others, main] : [...others, page.close]) : [...others, ...(main ? [main] : [])];
  if (page.close) page.close.className = main ? 'secondary' : 'primary';
  order.forEach((button, index) => { if (page.actions.children[index] !== button) page.actions.insertBefore(button, page.actions.children[index] || null); });
}
/* kind: false for a secondary action, true for the main action, 'destructive' for a destructive main action,
   'danger' for a destructive secondary action. A new main action demotes the previous one. Return in a text field
   presses the main action, as the default button does on the Mac; a textarea keeps Return for a new line. */
function action(page, title, work, kind = false) {
  const main = kind === true || kind === 'destructive';
  const button = element('button', title, kind === true ? 'primary' : kind === 'destructive' || kind === 'danger' ? 'destructive' : 'secondary');
  button.type = 'button';
  if (main) {
    for (const other of page.actions.querySelectorAll('[data-main="true"]')) { delete other.dataset.main; if (other.classList.contains('primary')) other.className = 'secondary'; }
    button.dataset.main = 'true';
    page.box.onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.target.matches('input:not([type=checkbox])') && !button.disabled) { e.preventDefault(); button.click(); } };
  }
  button.onclick = async () => { button.disabled = true; page.error.textContent = ''; try { await work(); } catch(e) { page.report(e); } finally { button.disabled = false; } };
  page.actions.append(button); arrange(page); return button;
}
function field(parent, label, type = 'text') {
  const wrapper = element('label',label); const input = element('input','','field'); input.type = type; if(type === 'password') input.autocomplete = 'new-password'; wrapper.append(input); parent.append(wrapper); return input;
}
/* A disclosure line with an SVG chevron that turns down when open. */
function summaryLine(text) { const node = element('summary'); node.append(icon('chevron', true), element('span', text)); return node; }
function group(parent) { const box = element('div', '', 'group'); parent.append(box); return box; }
/* A list row: a navigation row when it has an action, a read-only row otherwise. */
function row(parent, title, onclick, { detail, iconName, avatar, href, className } = {}) {
  const node = element(href ? 'a' : onclick ? 'button' : 'div', '', 'row' + (className ? ' ' + className : ''));
  if (href) { node.href = href; node.target = '_blank'; node.rel = 'noopener noreferrer'; }
  else if (onclick) { node.type = 'button'; node.onclick = () => void onclick(); }
  if (avatar) node.append(avatar); else if (iconName) node.append(icon(iconName));
  const text = element('span', '', 'row-text'), name = element('span', title, 'row-title'); name.dir = 'auto'; text.append(name);
  if (detail) { const line = element('span', detail, 'row-detail'); line.dir = 'auto'; text.append(line); }
  node.append(text);
  if ((onclick || href) && !className?.includes('destructive-row')) node.append(icon('chevron', true));
  parent.append(node); return node;
}
function download(data, name, type='application/octet-stream') {
  const url = URL.createObjectURL(new Blob([data],{type})); const link = element('a'); link.href=url; link.download=name; link.click(); setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function controlsKey() { return 'openstrudel.control.'+(state.homeId||location.origin); }
function rememberControl(id,pending) {
  const values=JSON.parse(localStorage.getItem(controlsKey())||'[]').filter(v=>v!==id);
  if(pending) values.push(id);
  localStorage.setItem(controlsKey(),JSON.stringify(values));
}
async function checkControls(page) {
  let completed=0,waiting=0;
  for(const id of JSON.parse(localStorage.getItem(controlsKey())||'[]')) {
    const result=await api('/v1/home/requests/'+encodeURIComponent(id));
    if(result.status==='canceled') { rememberControl(id,false); continue; }
    if(result.response) {
      rememberControl(id,false);
      if(result.response.status>=400) throw new Error(JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(result.response.body),c=>c.charCodeAt(0)))).error || t("Проверьте результат действия."));
      completed++;
    } else waiting++;
  }
  page.content.append(element('p',t("Завершено: {0}. Ожидают устройства: {1}.",completed,waiting)));
}
async function openTelegramSettings() {
  const page=modalPage('Telegram',t("Один бот для личного чата и групп сотрудников на этом устройстве."));
  const profile=state.profiles.find(p=>p.id===state.selected), suffix=profile?.deviceId?'?deviceId='+encodeURIComponent(profile.deviceId):'';
  const status=element('p',t("Проверяем подключение…"));status.setAttribute('role','status');page.content.append(status);
  try {
    const read=async()=>{const result=await api('/v1/integrations'+suffix);return result.telegram;};
    const telegram=await read();
    status.textContent=telegram.configured?t("Бот @")+telegram.botUsername+t(" подключён"):t("1. Создайте бота в BotFather командой /newbot.");
    if(!state.owner) return;
    if(!telegram.configured) {
      const help=element('a',t("Открыть BotFather"));help.href='https://t.me/BotFather';help.target='_blank';help.rel='noreferrer';page.content.append(help);
      const token=field(page.content,t("2. Вставьте ключ бота"),'password');
      action(page,t("Подключить бота"),async()=>{
        status.textContent=t("Проверяем ключ…");
        try {await api('/v1/integrations/telegram'+suffix,{method:'POST',body:JSON.stringify({token:token.value.trim()})});token.value='';await openTelegramSettings();}
        catch(e){status.textContent=t("Подключение не завершено.");throw e;}
      },true);
    } else {
      if(telegram.lastError) page.error.textContent=telegram.lastError;
      for (const chat of (telegram.chats||[]).filter(c=>c.chatId.startsWith('-')&&(!profile||c.profileId===profile.id))) {
        page.content.append(element('p',chat.title+' · '+(chat.replies==='mentions'?t("По @упоминанию или ответу"):t("По правилам сотрудника"))));
      }
      const paired=(telegram.chats||[]).some(chat=>!chat.chatId.startsWith('-')&&chat.allowedSenders.includes(chat.chatId));
      if(paired) page.content.append(element('p',t("Личный Telegram подключён.")));
      action(page,paired?t("Открыть Telegram"):t("Связать личный чат"),async()=>{
        const result=paired?{url:'https://t.me/'+telegram.botUsername}:await api('/v1/integrations/telegram/link'+suffix,{method:'POST',body:JSON.stringify({})});
        const link=element('a',t("Открыть чат в Telegram"));link.href=result.url;link.target='_blank';link.rel='noreferrer';page.content.replaceChildren(link,element('p',t("Нажмите «Начать» в Telegram.")));
        for(let i=0;!paired&&i<300&&$('modal-content').contains(page.box);i++) {
          await new Promise(resolve=>setTimeout(resolve,2000));
          const value=await read();if((value.chats||[]).some(chat=>!chat.chatId.startsWith('-')&&chat.allowedSenders.includes(chat.chatId))){page.content.append(element('p',t("Чат подключён. Можно писать боту.")));break;}
        }
      },!(paired&&profile));
      if(paired&&profile) {
        page.content.append(element('p',t("Добавьте «{0}» в группу. Все участники смогут обращаться к сотруднику через @упоминание бота или ответ ему. Личная переписка останется отдельно.",profile.name)));
        action(page,t("Добавить в группу…"),async()=>{
          const invite=await api('/v1/integrations/telegram/link'+suffix,{method:'POST',body:JSON.stringify({kind:'group',profileId:profile.id})});
          const url=invite.url?new URL(invite.url):null;
          if(url?.origin!=='https://t.me'||url.searchParams.get('startgroup')!==invite.code) throw new Error(t("Обновите OpenStrudel на устройстве этого сотрудника, чтобы подключить группу."));
          const link=element('a',t("Выбрать группу в Telegram"));link.href=invite.url;link.target='_blank';link.rel='noreferrer';page.content.append(link);
          page.content.append(element('p',t("Ссылка действует 10 минут. После выбора группы нажмите «Обновить».")));
        },true);
        action(page,t("Обновить"),()=>openTelegramSettings());
      }
    }
  } catch(e) {status.textContent='';page.report(e);}
}
async function bootstrapWeb() {
  await languageReady;
  paintHeader();
  clearInterval(state.refreshTimer);
  const key = new URLSearchParams(location.hash.slice(1)).get('invite');
  if (key) history.replaceState(null,'',location.pathname);
  try {
    const session = key ? await api('/auth/session',{method:'POST',body:JSON.stringify({key})}) : await api('/auth/session');
    if (!session.csrf) { showWelcome(); return; }
    state.csrf=session.csrf; state.owner=session.owner; state.authenticated=true; closeModal(); await refresh();
    if(state.owner) void api('/v1/settings/timezone',{method:'POST',body:JSON.stringify({timezone:Intl.DateTimeFormat().resolvedOptions().timeZone,initialize:true})}).catch(()=>{});
    restoreDraft();
    const transfer = JSON.parse(localStorage.getItem('openstrudel.transfer') || 'null');
    if (transfer) await watchTransfer(transfer);
    state.refreshTimer=setInterval(()=>{ if(!document.hidden && !state.loading) void refresh(); },5000);
  } catch(e) { showWelcome(key ? e : null); }
}
/* The first screen for a browser that is not signed in. */
function showWelcome(error) {
  const page=modalPage(t("Подключитесь к своей команде"),t("Откройте приглашение для браузера из настроек OpenStrudel на Mac или сервере с вашими сотрудниками."),{close:false,locked:true});
  page.box.prepend(characterImage(null,96));
  const input=field(page.content,t("Ссылка с приглашением")); input.value=state.invitationDraft||''; input.type='url'; input.autocomplete='off';
  const language=languageField(page,()=>{state.invitationDraft=input.value;showWelcome();$('interface-language').focus();});
  language.className='language-line'; page.box.append(language);
  if(error) page.report(error);
  const connect=action(page,t("Подключиться"),async()=>{
    let url; try { url=new URL(input.value.trim()); } catch { throw new Error(t("В ссылке нет приглашения.")); }
    if(url.origin!==location.origin) throw new Error(t("Это приглашение для другого устройства. Откройте его адрес в браузере."));
    const invite=new URLSearchParams(url.hash.slice(1)).get('invite'); if(!invite) throw new Error(t("В ссылке нет приглашения."));
    const session=await api('/auth/session',{method:'POST',body:JSON.stringify({key:invite})});
    state.csrf=session.csrf; state.owner=session.owner; closeModal(); await bootstrapWeb();
  },true);
  const ready=()=>{connect.disabled=!input.value.trim();}; input.addEventListener('input',ready); ready();
  input.focus();
}
window.addEventListener('hashchange',()=>{ if(new URLSearchParams(location.hash.slice(1)).has('invite')) void bootstrapWeb(); });
async function openHomeSettings() {
  state.back=null;
  const page=modalPage(t("Настройки"),t("Сотрудники и переписка находятся на этом устройстве."));
  languageField(page,async()=>{await openHomeSettings();$('interface-language').focus();});
  const via=(label,fn)=>()=>{state.back={label:t("Настройки"),open:openHomeSettings,row:label};return fn();};
  const entries=state.owner ? [[t("Устройства"),openDevices],[t("Настройки сотрудника"),openCurrentAgent],[t("Аккаунты и лимиты"),openAccounts],[t("Модель и скорость"),()=>openModelSettings()],[t("Голос"),()=>openSpeechSettings()],[t("Резервная копия"),openSettings],['Telegram',openTelegramSettings]] : [[t("Аккаунты и лимиты"),openAccounts]];
  const list=group(page.content);
  for(const [label,fn] of entries) row(list,label,via(label,fn));
  if(state.hostingOrigin) {
    const hosting=new URL(state.hostingOrigin);
    if(hosting.protocol==='https:'||hosting.protocol==='http:') row(list,t("Серверы: создание и продление"),null,{href:hosting.href});
  }
  row(group(page.content),t("Выйти на этом устройстве"),via(t("Выйти на этом устройстве"),openDeviceSignOut),{className:'destructive-row'});
}
async function openDevices() {
  const here={label:t("Устройства"),open:openDevices,back:state.back}, sub=fn=>(...args)=>{state.back=here;return fn(...args);};
  const page=modalPage(t("Устройства"),t("Сотрудники остаются на устройстве, где созданы. Для работы с несколькими устройствами откройте приложение OpenStrudel."));
  try {
    const data=await api('/v1/devices'); state.devices=data.devices;
    if(JSON.parse(localStorage.getItem(controlsKey())||'[]').length) action(page,t("Проверить сохранённые действия"),()=>checkControls(page));
    const control=await api('/v1/home');
    const list=group(page.content);
    for(const device of data.devices) row(list,device.name,null,{detail:t("{0} · Сотрудников: {1}",device.online?t("На связи"):t("Не на связи"),device.agents)});
    if(control.operations?.length) { const moves=group(page.content); for(const operation of control.operations) row(moves,t("Проверить перенос сотрудника"),sub(()=>watchAgentMove(operation.id))); }
    if(state.owner) {
      action(page,t("Поделиться доступом…"),async()=>{
        state.back=here; const next=modalPage(t("Кому дать доступ?"),t("На своём устройстве вы сохраните все права. Коллега сможет работать с сотрудниками, но не управлять аккаунтами и доступом."));
        const choices=group(next.content);
        for(const [owner,title] of [[true,t("Моему устройству")],[false,t("Коллеге")]]) row(choices,title,async()=>{
          try {
            const invite=await api('/v1/mobile/pairing',{method:'POST',body:JSON.stringify({owner})});
            const url=invite.shareUrl||'https://waiwai.is/openstrudel/connect.html#'+encodeURIComponent(invite.url);
            next.content.replaceChildren(element('p',t("Ссылка действует сутки и подключает одно устройство.")));
            const text=field(next.content,t("Ссылка подключения"),'password');text.value=url;text.readOnly=true;
            action(next,t("Скопировать ссылку"),async()=>{await navigator.clipboard.writeText(url);next.error.textContent=t("Ссылка скопирована. Продолжите на другом устройстве.");},true);
          } catch(e) { next.report(e); }
        });
      },true);
    }
  } catch(e) { page.report(e); }
}
/* The assistant's details, as the Mac details sheet: the character, the name and the role, what the assistant does,
   its look, its pages, its account, and deleting it last. Pages opened from here lead back here with the edits kept. */
async function openCurrentAgent(draft) {
  const agent=state.selected||'main', profile=state.profiles.find(p=>p.id===agent), name=profile?.name||'OpenStrudel', back=state.back;
  const page=modalPage(t("Сотрудник"),'',{close:'cancel'});
  let nameField=null, instructions=null, editor=null, select=null, initialAccount='';
  const edits=()=>({name:nameField?.value,instructions:instructions?.value,appearance:editor?.value(),account:select?.value});
  const here=row=>({label:name,open:()=>openCurrentAgent(edits()),row,back});
  const sub=(label,fn)=>()=>{state.back=here(label);return fn();};
  const header=element('div','','details-header'), avatar=element('span','','avatar'), titles=element('div','','details-titles');
  avatar.append(characterImage(profile?agentAppearance(profile):null,64)); avatar.classList.toggle('offline',isOffline(profile));
  if(profile) {
    nameField=element('input','','field details-name'); nameField.dir='auto'; nameField.maxLength=80; nameField.autocomplete='off';
    nameField.value=draft?.name??profile.name; nameField.setAttribute('aria-label',t("Имя сотрудника")); titles.append(nameField);
  } else titles.append(element('span','OpenStrudel','details-name'));
  const role=profile?profile.purpose:t("Помощник для ваших задач");
  if(role) { const line=element('span',role,'details-role'); line.dir='auto'; titles.append(line); }
  header.append(avatar,titles); page.content.append(header);
  if(profile) {
    const label=element('label',t("Чем занимается сотрудник")); instructions=element('textarea','','field reading'); instructions.rows=5; instructions.dir='auto'; instructions.maxLength=12000;
    instructions.value=draft?.instructions??profile.instructions??''; label.append(instructions);
    page.content.append(label,element('p',t("Опишите задачи и правила, которым он должен следовать."),'hint'));
  }
  if(profile && state.appearanceVersion===1) { editor=appearanceEditor(draft?.appearance||agentAppearance(profile),look=>avatar.replaceChildren(characterImage(look,64))); page.content.append(editor.root); }
  const list=group(page.content);
  row(list,t("Модель и скорость"),sub(t("Модель и скорость"),()=>openModelSettings(agent)));
  row(list,t("Сервисы"),sub(t("Сервисы"),openServices));
  row(list,t("Управление компьютером"),sub(t("Управление компьютером"),openComputerSettings));
  let danger=null;
  if(profile && state.owner) { danger=group(page.content); row(danger,t("Удалить сотрудника…"),()=>confirmDelete(),{className:'destructive-row'}); }
  const add=(...nodes)=>danger?danger.before(...nodes):page.content.append(...nodes);
  function confirmDelete() {
    const device=(state.devices||[]).find(d=>d.id===(profile.deviceId||state.nodeId))?.name||'OpenStrudel', from=here(t("Удалить сотрудника…"));
    const confirm=modalPage(t("Удалить «{0}»?",profile.name),t("Сотрудник, переписка и расписания будут удалены с устройства «{0}». Отменить удаление нельзя.",device),{close:'cancel',back:null});
    confirm.close.onclick=()=>void goBack(from);
    action(confirm,t("Удалить"),async()=>{
      await api('/v1/profiles/'+encodeURIComponent(profile.id),{method:'DELETE'});
      state.profiles=state.profiles.filter(p=>p.id!==profile.id);
      closeModal(); await selectAgent(null); await refresh();
    },'destructive');
  }
  const save=action(page,t("Сохранить"),async()=>{
    if(profile) {
      const changes={name:nameField.value.trim(),instructions:instructions.value.trim()}, look=editor?.value();
      const lookChanged=Boolean(editor)&&JSON.stringify(look)!==JSON.stringify(agentAppearance(profile));
      if(changes.name!==profile.name||changes.instructions!==(profile.instructions||'')||lookChanged) {
        const result=await api('/v1/profiles/'+encodeURIComponent(profile.id),{method:'PATCH',body:JSON.stringify({...changes,...(lookChanged?{appearance:look}:{})})});
        if(lookChanged&&JSON.stringify(result.profile?.appearance)!==JSON.stringify(look)) throw new Error(t("Обновите OpenStrudel на устройстве этого сотрудника, чтобы сохранить образ."));
      }
    }
    if(select && select.value!==initialAccount) await api('/v1/agents/'+agent+'/accounts',{method:'POST',body:JSON.stringify({accountIds:select.value?[select.value]:null})});
    closeModal();await refresh();
  },true);
  if(nameField) { const named=()=>{save.disabled=!nameField.value.trim();}; nameField.addEventListener('input',named); named(); }
  try {
    const control=await api('/v1/home'), deviceId=profile?.deviceId||control.home.mainNodeId;
    const device=control.devices.find(d=>d.id===deviceId);
    add(element('p',t("Работает на «{0}».",device?.name||t("вашем устройстве"))));
    const data=await api('/v1/accounts?deviceId='+encodeURIComponent(deviceId)), policy=await api('/v1/agents/'+agent+'/accounts');
    const label=element('label',t("Аккаунт OpenAI")); select=element('select','','field'); label.append(select); add(label);
    add(element('p',t("Настройки изменят новые поручения. Уже начатая работа продолжится с прежним аккаунтом."),'hint'));
    const defaultOption=element('option',t("По умолчанию")); defaultOption.value=''; select.append(defaultOption);
    for(const account of data.accounts) { const option=element('option',(account.account.email||account.name)+' · '+accountPlan(account.account.planType)); option.value=account.id; select.append(option); }
    if(policy.accountIds?.length===1) select.value=policy.accountIds[0];
    else if(policy.accountIds?.length>1) add(element('p',t("Выбран отдельный порядок аккаунтов. Новый выбор заменит его.")));
    initialAccount=select.value;
    if([...select.options].some(option=>option.value===draft?.account)) select.value=draft.account;
  } catch(e) { page.report(e); }
}
async function openServices() {
  const conversationId=state.conversationID;
  const page=modalPage(t("Сервисы"),t("Подключения, которыми сотрудник может пользоваться в этом чате."));
  const status=element('p',t("Проверяем подключение…"));status.setAttribute('role','status');page.content.append(status);
  const list=group(page.content), suffix='?conversationId='+encodeURIComponent(conversationId||'');
  let loading=false, starting=false, disposed=false, pending=null;
  async function cancelPending() {
    const flow=pending;pending=null;cancel.hidden=true;
    if(flow) {flow.popup?.close();try {await api('/v1/connections/oauth/'+flow.id+suffix,{method:'DELETE'});} catch(e) {if(e.status!==404)throw e;}}
  }
  const cancel=action(page,t("Отменить вход"),async()=>{await cancelPending();await refreshServices();});cancel.hidden=true;
  const onFocus=()=>void refreshServices();window.addEventListener('focus',onFocus);
  page.box.addEventListener('dismiss',()=>{disposed=true;window.removeEventListener('focus',onFocus);void cancelPending().catch(()=>{});},{once:true});
  async function refreshServices() {
    if(disposed || loading || !$('modal-content').contains(page.box)) return;
    loading=true;page.error.textContent='';status.textContent=t("Проверяем подключение…");
    try {
      if(!conversationId) throw new Error(t("Откройте чат сотрудника, для которого добавляете расширение."));
      const data=await api('/v1/connections'+suffix+'&refresh=true');
      if(disposed)return;
      if(pending&&(data.connections||[]).some(connection=>connection.id===pending.service&&connection.connected)) {pending=null;cancel.hidden=true;}
      list.replaceChildren();status.textContent=data.notice||'';
      for(const connection of data.connections||[]) {
        const ready=connection.connected, unknown=connection.status==='unknown', disabled=connection.status==='disabled', unavailable=connection.status==='unavailable';
        const detail=ready?t("Подключено"):unknown?t("Не удалось проверить подключение"):disabled?t("Выключено"):unavailable?t("Нет связи с сервисом"):t("Нужен вход");
        const item=row(list,connection.name,null,{detail:[connection.detail,detail].filter(Boolean).join(' · ')});
        if(state.owner&&!ready&&!disabled) {
          const button=element('button',t("Подключить"),'secondary');button.type='button';button.disabled=Boolean(pending)||starting;button.setAttribute('aria-label',t("Подключить")+' '+connection.name);item.append(button);
          button.onclick=async()=>{
            // Open while the click is active, so browsers do not block sign-in.
            const popup=window.open('about:blank','_blank');if(popup)popup.opener=null;
            starting=true;for(const other of list.querySelectorAll('button'))other.disabled=true;page.error.textContent='';status.textContent=t("Подключаем…");
            try {
              const result=await api('/v1/connections/connect',{method:'POST',body:JSON.stringify({id:connection.id,conversationId,callback:'web'})});
              if(!result.url) {popup?.close();await refreshServices();return;}
              if(disposed) {popup?.close();if(result.signInId)await api('/v1/connections/oauth/'+result.signInId+suffix,{method:'DELETE'});return;}
              const url=new URL(result.url);if(!['https:','http:'].includes(url.protocol))throw new Error(t("Не удалось прочитать ответ сервиса. Попробуйте ещё раз."));
              if(result.signInId) {pending={id:result.signInId,service:connection.id,popup};cancel.hidden=false;for(const other of list.querySelectorAll('button'))other.disabled=true;}
              if(popup)popup.location.href=url.href;
              status.replaceChildren(element('span',t("Завершите вход в браузере и вернитесь сюда.")));
              if(!popup) {const link=element('a',t("Продолжить вход"));link.href=url.href;link.target='_blank';link.rel='noopener noreferrer';status.append(document.createTextNode(' '),link);}
            } catch(e) {popup?.close();status.textContent='';page.report(e);}
            finally {starting=false;for(const other of list.querySelectorAll('button'))other.disabled=Boolean(pending);}
          };
        }
      }
      if(!data.connections?.length&&!data.notice)status.textContent=t("Подключений пока нет. Добавьте сервис в приложении OpenStrudel.");
    } catch(e) {status.textContent='';page.report(e);}
    finally {loading=false;}
  }
  action(page,t("Обновить"),refreshServices);
  await refreshServices();
}
async function watchAgentMove(id) {
  const page=modalPage(t("Перенос сотрудника"),t("Можно закрыть окно. Состояние операции сохранено."));
  let retry;
  const labels={waiting:t("Ждём завершения принятых поручений"),preparing:t("Готовим копию"),staging:t("Проверяем копию"),releasing:t("Останавливаем прежнюю копию"),activating:t("Включаем новую копию"),canceling:t("Отменяем подготовку"),canceled:t("Подготовка отменена"),completed:t("Сотрудник перенесён"),attention:t("Нужна проверка устройств")};
  const check=async()=>{
    const result=await api('/v1/home/operations/'+encodeURIComponent(id));
    page.content.replaceChildren(element('p',labels[result.phase]||t("Проверяем перенос")));
    page.error.textContent=result.error||'';
    for(const warning of result.warnings||[]) page.content.append(element('p',warning));
    if(result.phase==='attention'&&!retry) retry=action(page,t("Продолжить перенос"),async()=>{await api('/v1/home/operations/'+id+'/retry',{method:'POST',body:'{}'});await check();},true);
    if(retry) retry.hidden=result.phase!=='attention';
    if(result.phase==='completed') { await refresh(); return true; }
    return ['canceled','attention'].includes(result.phase);
  };
  action(page,t("Проверить состояние"),check);
  try { for(let n=0;n<30 && $('modal-content').contains(page.box);n++) { if(await check()) break; await new Promise(r=>setTimeout(r,1000)); } } catch(e) { page.report(e); }
}
async function watchTransfer(value) {
  const page = modalPage(t("Передача управления"),t("Проверяем подтверждение нового подключения. Закрытие окна не отменяет передачу."));
  const check = async () => {
    const result = await api('/v1/home/operations/' + encodeURIComponent(value.operationId));
    if (result.phase === 'completed' || result.phase === 'active') {
      localStorage.removeItem('openstrudel.transfer');
      page.content.replaceChildren(element('p',t("Подключение изменилось. Создайте ссылку для браузера на новом устройстве.")));
      const link=element('a',t("Открыть устройство")); link.href=value.url; link.rel='noreferrer'; page.content.append(link);
      return true;
    }
    if (result.phase === 'canceled' || result.phase === 'activation_failed') throw new Error(result.error || t("Передача не завершена. Проверьте состояние устройств."));
    return false;
  };
  action(page,t("Проверить состояние"),check,true);
  try { for(let i=0;i<20;i++) { if(await check()) return; if(!$('modal-content').contains(page.box)) return; await new Promise(r=>setTimeout(r,1000)); } }
  catch(e) { page.report(e); }
}
async function openAccounts(deviceId, force=false) {
  const here={label:t("Аккаунты и лимиты"),open:()=>openAccounts(deviceId),back:state.back};
  const page=modalPage(t("Аккаунты и лимиты"),t("Подписка OpenAI и отдельный баланс кредитов."));
  const list=element('div','','accounts');
  const loading=element('p',t("Загружаем аккаунты и лимиты…"));loading.setAttribute('role','status');page.content.append(loading);
  try {
    const devices=state.devices || (await api('/v1/devices')).devices;
    const selector=element('select','','field'); selector.setAttribute('aria-label',t("Устройство"));
    for(const device of devices) { const option=element('option',device.name); option.value=device.id; selector.append(option); }
    selector.value=deviceId || state.nodeId||devices[0]?.id; deviceId=selector.value;
    selector.onchange=()=>void openAccounts(selector.value); if(devices.length>1)page.content.append(selector);
    page.content.append(list);
    const suffix='?deviceId='+encodeURIComponent(deviceId);
    const data=await api('/v1/accounts'+suffix+'&refresh='+force);loading.remove();
    for(const [i,entry] of data.accounts.entries()) {
      const card=element('div','','account-summary');
      const title=entry.displayName || (["Основной","Аккаунт","OpenAI","Account","ChatGPT",""].includes(entry.name)?entry.account.email||'ChatGPT':entry.name);
      card.append(element('strong',title));
      if(entry.account.email&&entry.account.email!==title)card.append(element('p',entry.account.email));
      const category=accountCategory(entry.account.planType);
      card.append(element('p',entry.account.issue==='unavailable'?t('Не удалось проверить аккаунт'):entry.account.connected?[accountPlan(entry.account.planType),category].filter(Boolean).join(' · '):t('Нужен вход')));
      if(data.accounts.filter(other=>other.account.email===entry.account.email&&other.account.planType===entry.account.planType).length>1)card.append(element('small',t('Connection {0}',entry.id.slice(-6))));
      if(i===0&&data.accounts.length>1)card.append(element('small',t('По умолчанию для новых поручений')));
      if(entry.account.connected) {
      const limits=element('details');limits.append(summaryLine(t('Limits and credits')));card.append(limits);
      const usage=entry.usage || {windows:[],unavailable:true};
      if(usage.windows.length) for(const window of usage.windows) {
        const name=window.windowDurationMins===300?t('5 часов'):window.windowDurationMins===10080?t('Неделя'):window.windowDurationMins===1440?t('Сутки'):i18n.error(window.name);
        limits.append(element('p',name+' · '+(window.remainingPercent==null?t('Нет данных'):t('{0}% осталось',Math.round(window.remainingPercent)))));
        if(window.remainingPercent!=null) {const progress=element('progress');progress.max=100;progress.value=Math.min(100,Math.max(0,window.remainingPercent));progress.setAttribute('aria-label',name);limits.append(progress);}
        if(window.resetsAt)limits.append(element('small',t('Сброс {0}',new Date(window.resetsAt*1000).toLocaleString(i18n.language,{dateStyle:'medium',timeStyle:'short'}))));
      } else limits.append(element('p',usage.unavailable?t('Не удалось получить остатки. Обновите список.'):t('OpenAI не передал лимиты подписки.')));
      const credits=usage.credits;limits.append(element('p',t('Кредиты')+': '+(credits?.unlimited?t('Без ограничений'):credits?.balance??(credits?.hasCredits?t('Доступны · баланс не передан'):credits?t('Нет кредитов'):t('Баланс не передан')))));
      const resets=usage.resetCredits;
      if(resets) {limits.append(element('p',t('Extra limit resets')+': '+resets.availableCount));if(resets.nextExpiresAt)limits.append(element('small',t('Next expiry: {0}',new Date(resets.nextExpiresAt*1000).toLocaleString(i18n.language,{dateStyle:'medium',timeStyle:'short'}))));}
      if(usage.checkedAt)limits.append(element('small',t('Updated {0}',new Date(usage.checkedAt).toLocaleTimeString(i18n.language,{hour:'numeric',minute:'2-digit'}))));
      }
      if(data.canManage) {
        const more=element('details'), summary=summaryLine(t('Действия с аккаунтом'));more.append(summary);
        const rename=element('button',t('Rename account…'),'secondary');
        rename.onclick=()=>{
          state.back=here; const edit=modalPage(t('Rename account'),t('Choose a name you recognise. Your OpenAI account stays the same.'),{close:'cancel'});
          const input=field(edit.content,t('Название аккаунта'));input.value=title;input.maxLength=80;
          const save=action(edit,t('Сохранить'),async()=>{await api(`/v1/accounts/${entry.id}`+suffix,{method:'POST',body:JSON.stringify({name:input.value.trim()})});await goBack(here);},true);
          input.oninput=()=>{save.disabled=!input.value.trim();};input.focus();input.select();
        };more.append(rename);
        const login=element('button',entry.account.connected?t("Войти заново"):t("Войти в OpenAI"),'secondary');
        login.onclick=()=>{state.back=here;void startAccountLogin(entry.id,deviceId);};(entry.account.connected?more:card).append(login);
        if(i>0&&entry.account.connected) { const use=element('button',t("Использовать первым"),'secondary'); use.onclick=async()=>{try{await api(`/v1/accounts/${entry.id}/priority`+suffix,{method:'POST',body:'{}'}); await openAccounts(deviceId);}catch(e){page.report(e);}}; more.append(use); }
        card.append(more);
      }
      list.append(card);
    }
    action(page,t("Обновить остатки"),()=>openAccounts(deviceId,true));
    if(data.canManage) action(page,t("Добавить аккаунт"),async()=>{ const entry=await api('/v1/accounts'+suffix,{method:'POST',body:JSON.stringify({name:t("Аккаунт")})}); state.back=here; await startAccountLogin(entry.id,deviceId); });
  } catch(e) { page.report(e); action(page,t("Повторить"),()=>openAccounts(deviceId)); }
  finally { loading.remove(); }
}
async function startAccountLogin(accountId,deviceId) {
  const back=state.back, done=()=>back?goBack(back):openAccounts(deviceId);
  const page=modalPage(t("Вход в OpenAI"),t("Войдите в свой аккаунт на сайте OpenAI и подтвердите подключение этого устройства."));
  const base=`/v1/accounts/${encodeURIComponent(accountId)}/login`, suffix='?deviceId='+encodeURIComponent(deviceId);
  try {
    const login=await api(base+suffix,{method:'POST',body:'{}'});
    const code=element('p',login.userCode,'code-display'); code.dir='ltr'; page.content.append(code);
    const link=element('a',t("Открыть OpenAI")); const url=new URL(login.verificationUrl); if(url.protocol!=='https:' || url.hostname!=='auth.openai.com') throw new Error(t("OpenAI вернул неизвестный адрес входа."));
    link.href=url.href; link.target='_blank'; link.rel='noopener noreferrer'; page.content.append(link);
    action(page,t("Проверить вход"),async()=>{ const result=await api(base+'/'+encodeURIComponent(login.loginId)+suffix); if(result.status==='completed') await done(); else if(result.status==='failed'||result.status==='canceled') throw new Error(result.error || t("Вход отменён. Начните снова.")); else page.error.textContent=t("Завершите вход на сайте OpenAI."); },true);
    action(page,t("Отменить вход"),async()=>{await api(base+'/'+encodeURIComponent(login.loginId)+suffix,{method:'DELETE'}); await done();},'danger');
  } catch(e) { page.report(e); }
}
async function openCreateAgent() {
  const page=modalPage(t("Новый сотрудник"),t("Дайте имя и опишите его задачу."),{close:'cancel'});
  const name=field(page.content,t("Имя")); name.dir='auto';
  const descriptionLabel=element('label',t("Инструкции")), description=element('textarea','','field'); description.rows=4; description.dir='auto'; descriptionLabel.append(description); page.content.append(descriptionLabel);
  const selectorLabel=element('label',t("Где работает")), selector=element('select','','field'); selectorLabel.append(selector); page.content.append(selectorLabel);
  try {
    const data=await api('/v1/devices'); state.devices=data.devices;
    for(const device of data.devices) { const option=element('option',device.name); option.value=device.id; option.disabled=!device.online; selector.append(option); }
    selector.value=state.nodeId||data.devices[0]?.id;
    selectorLabel.hidden=data.devices.length<2;
  } catch(e) { page.report(e); }
  const creationId=crypto.randomUUID();

  action(page,t("Создать"),async()=>{
    const result=await api('/v1/profiles',{method:'POST',headers:{'idempotency-key':creationId},body:JSON.stringify({name:name.value,defaultName:t("Новый сотрудник"),instructions:description.value,deviceId:selector.value,creationId})});
    if(!result.profile) throw new Error(t("Создание ещё выполняется. Проверьте список сотрудников после подключения устройства."));
    closeModal(); await refresh(); await selectAgent(result.profile.id);
  },true);
  name.focus();
}
function openNavigation() {
  const page=modalPage(t("Сотрудники"));
  const list=group(page.content);
  for(const profile of [null,...state.profiles]) {
    const avatar=element('span','','avatar'); avatar.append(characterImage(profile?agentAppearance(profile):null,36)); avatar.classList.toggle('offline',isOffline(profile));
    const current=(state.selected||null)===(profile?.id||null);
    const button=row(list,profile?.name||'OpenStrudel',async()=>{closeModal();try{await selectAgent(profile?.id||null);}catch(e){notify(e.message);}},{avatar,detail:isOffline(profile)?t("Нет связи"):profile?previewLine(profile.preview)||profile.purpose||t("Напишите, что нужно."):t("Помощник для ваших задач"),className:'agent-row'+(current?' current':'')});
    if(current) button.setAttribute('aria-current','page');
  }
  // Symbols sit in the avatar column so every title above and below starts on one edge.
  const symbol=name=>{const box=element('span','','avatar symbol');box.append(icon(name));return box;};
  const more=group(page.content);
  row(more,t("Настройки"),openHomeSettings,{avatar:symbol('gear')});
  row(more,t("Новый сотрудник"),openCreateAgent,{avatar:symbol('plus')});
}
async function sendDraft(event) {
  event.preventDefault(); const text=$('draft').value.trim(), files=state.attachments;
  if(files.some(file=>!file.id)) return;
  const running=runningMessage();
  if(!text && !files.length) { if(running) await stopReply(running); return; }
  if(state.loading) return;
  let draft; try { draft = saveDraft(); } catch(e) { notify(e.message); return; }
  $('draft').value=''; state.attachments=[]; renderAttachments(); syncDraft();
  await deliver({...draft,profile:state.selected||null,conversationId:state.chat||null,...(running?{mode:state.sendMode}:{})});
}
/* The plus attaches up to six files of 25 MB. Each one uploads to the conversation at once and shows as a tile
   inside the glass; Send waits until every tile has its id. The browser has no speech engine, so there is no microphone. */
$('attach').onclick=()=>{ const picker=document.createElement('input'); picker.type='file'; picker.multiple=true; picker.onchange=()=>void attachFiles([...picker.files]); picker.click(); };
$('send-mode').onclick=()=>{ state.sendMode=state.sendMode==='queue'?'steer':'queue'; syncDraft(); };
async function attachFiles(files) {
  const list=state.attachments, conversationId=state.conversationID, room=6-list.length;
  if(!conversationId) return;
  if(files.length>room) notify(t("Можно прикрепить до шести файлов."));
  const uploads=[];
  for(const file of files.slice(0,Math.max(0,room))) {
    if(!file.size || file.size>25*1024*1024) { notify(t("Выберите файл до 25 МБ")); continue; }
    const entry={name:file.name,size:file.size,mimeType:file.type||'application/octet-stream'}; list.push(entry); uploads.push([entry,file]);
  }
  renderAttachments(); syncDraft();
  await Promise.all(uploads.map(async([entry,file])=>{
    try {
      const contentBase64=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result).split(',')[1]||'');reader.onerror=()=>reject(reader.error);reader.readAsDataURL(file);});
      const result=await api('/v1/conversations/'+encodeURIComponent(conversationId)+'/files',{method:'POST',body:JSON.stringify({id:crypto.randomUUID(),name:entry.name,mimeType:file.type||undefined,contentBase64})});
      entry.id=result.attachment.id; entry.mimeType=result.attachment.mimeType;
    } catch(e) { list.splice(list.indexOf(entry),1); notify(e.message||t("Не удалось добавить файл")); }
    if(list===state.attachments) { renderAttachments(); try { saveDraft(); } catch(e) { notify(e.message); } syncDraft(); }
  }));
}
function renderAttachments() {
  const box=$('composer-files'); box.hidden=!state.attachments.length;
  box.replaceChildren(...state.attachments.map(file=>{
    const tile=element('div','','attachment'+(file.id?'':' uploading')), text=element('span','','attachment-text'), name=element('span',file.name,'file-name'); name.dir='auto';
    text.append(name,element('span',file.id?fileSize(file.size):t("Добавляем файлы"),'file-size'));
    const remove=element('button','','remove'); remove.type='button'; remove.setAttribute('aria-label',t("Remove {0}",file.name)); remove.title=t("Remove {0}",file.name); remove.append(icon('xmark'));
    remove.onclick=()=>{ state.attachments=state.attachments.filter(other=>other!==file); renderAttachments(); try { saveDraft(); } catch(e) { notify(e.message); } syncDraft(); $('draft').focus(); };
    tile.append(icon('doc'),text,remove); return tile;
  }));
}
/* The message shows in the transcript at once and its saved draft stays until the device accepts it. A message
   that fails keeps its bubble with the reason and a retry under it; the same id lets the retry find it. */
async function deliver(message) {
  if(state.loading) return;
  const {error,createdAt,...draft}=message, key=draftKey();
  state.loading=true; notify('');
  state.pending=[...state.pending.filter(item=>item.externalId!==draft.externalId),{...draft,createdAt:new Date().toISOString()}];
  renderMessages(true);
  try {
    const result=await api('/v1/messages?async=true',{method:'POST',body:JSON.stringify({...draft,attachments:draft.attachments?.length?draft.attachments.map(file=>file.id):undefined,channel:'api',externalChatId:'home'})});
    if (result.operationId) {
      const queue=readOutbox(); if(!queue.some(item=>item.externalId===draft.externalId)) queue.push({...draft,operationId:result.operationId}); saveOutbox(queue);
    }
    if(JSON.parse(localStorage.getItem(key)||'null')?.externalId===draft.externalId) localStorage.removeItem(key);
    renderMessages(true);
    await refresh();
    state.pending=state.pending.filter(item=>item.externalId!==draft.externalId);
  } catch(e) {
    const reason=e.status&&e.status<500?e.message:t("Не удалось подтвердить доставку. Повтор проверит это же сообщение.");
    state.pending=state.pending.map(item=>item.externalId===draft.externalId?{...item,error:reason}:item);
  }
  finally {state.loading=false;syncDraft();renderMessages();}
}
async function stopReply(message) {
  $('send').disabled=true;
  try { await api(`/v1/conversations/${encodeURIComponent(state.conversationID)}/messages/${encodeURIComponent(message.id)}/cancel`,{method:'POST',body:'{}'}); await refresh(); }
  catch(e) { notify(e.message); syncDraft(); }
}
function draftKey() { return 'openstrudel.draft.' + (state.homeId || location.origin) + '.' + (state.chat || state.selected || 'main'); }
function saveDraft() {
  const text=$('draft').value, attachments=state.attachments.filter(file=>file.id).map(({id,name,size,mimeType})=>({id,name,size,mimeType}));
  const previous=JSON.parse(localStorage.getItem(draftKey()) || 'null');
  const same=previous?.text===text && JSON.stringify(previous.attachments||[])===JSON.stringify(attachments);
  const draft=same ? previous : { text, attachments, profile:state.selected, conversationId:state.chat, externalId:crypto.randomUUID() };
  try { localStorage.setItem(draftKey(),JSON.stringify(draft)); } catch { throw new Error(t("Не удалось сохранить черновик в браузере. Освободите место перед отправкой.")); }
  return draft;
}
function restoreDraft() {
  const draft=JSON.parse(localStorage.getItem(draftKey()) || 'null'); $('draft').value=draft?.text || '';
  state.attachments=(draft?.attachments||[]).map(file=>({...file})); renderAttachments();
  syncDraft();
}
function outboxKey() { return 'openstrudel.outbox.' + (state.homeId || location.origin); }
function readOutbox() { return JSON.parse(localStorage.getItem(outboxKey()) || '[]'); }
function saveOutbox(items) { localStorage.setItem(outboxKey(),JSON.stringify(items)); }
async function checkOutbox() {
  const queue=readOutbox(), delivered=new Set(state.messages.map(m=>m.externalId));
  for(const item of queue) {
    if(delivered.has(item.externalId)) continue;
    try {
      const result=await api('/v1/home/requests/' + encodeURIComponent(item.operationId));
      if(result.status==='canceled') item.error=t("Отменено до отправки устройству");
      else if(result.response?.status>=400 && result.response.status!==410) {
        const bytes=Uint8Array.from(atob(result.response.body),c=>c.charCodeAt(0));
        item.error=JSON.parse(new TextDecoder().decode(bytes)).error || t("Проверьте результат в чате перед новой отправкой");
      }
    } catch { /* Receipt remains durable while Home reconnects. */ }
  }
  const updated=new Map(queue.map(item=>[item.operationId,item]));
  saveOutbox(readOutbox().filter(item=>!delivered.has(item.externalId)).map(item=>updated.get(item.operationId)||item));
}
$('draft').addEventListener('input',()=>{try{saveDraft();}catch(e){notify(e.message);$('send').disabled=true;}});
languageReady.then(()=>bootstrapWeb()).catch(()=>{ const retry=element('button','Reload','secondary');retry.onclick=()=>location.reload();$('connection-notice').replaceChildren(element('div','Couldn’t load the interface. Reload to try again.'),retry); });

async function openDeviceSignOut() {
  const page=modalPage(t("Выйти на этом устройстве?"),t("Сотрудники, переписка, файлы и расписания сохранятся на ваших устройствах. Команда продолжит работать, пока её Mac или сервер включён. Для возвращения понадобится новое приглашение."),{close:'cancel'});
  const back=state.back; if(back) page.close.onclick=()=>void goBack(back);
  if($('draft').value.trim()) page.content.append(element('p',t("Черновик останется в этом браузере для повторного подключения к этой команде.")));
  action(page,t("Выйти"),async()=>{ saveDraft(); await api('/auth/logout',{method:'POST'}); clearInterval(state.refreshTimer); location.reload(); },'destructive');
  if(state.owner && state.archiveVersion===1) action(page,t("Сначала сохранить копию…"),openSettings);
}

async function openModelSettings(agent, deviceId, conversationId) {
  const inherits=Boolean(agent||conversationId);
  const page=modalPage(t("Модель и скорость"),conversationId?t("Только для этого чата. Начатая работа продолжится с прежними настройками."):inherits?t("Для этого сотрудника. Начатая работа продолжится с прежними настройками."):t("По умолчанию для сотрудников устройства. Можно выбрать другую модель в настройках сотрудника."));
  const status=element('p',t("Получаем доступные модели…"));status.setAttribute('role','status');page.content.append(status);
  try {
    const control=await api('/v1/home');
    if(!inherits) {
      const label=element('label',t("Устройство")), device=element('select','','field');label.append(device);
      for(const item of control.devices) { const o=element('option',item.name+(item.online?'':t(" · нет связи")));o.value=item.id;device.append(o); }
      deviceId ||= control.home.nodeId; device.value=deviceId;
      device.onchange=()=>void openModelSettings(undefined,device.value);page.content.prepend(label);
      label.hidden=control.devices.length<2;
    }
    const query=new URLSearchParams();if(!conversationId&&agent)query.set('agentId',agent);if(deviceId)query.set('deviceId',deviceId);
    const path=(conversationId?'/v1/conversations/'+encodeURIComponent(conversationId)+'/model':'/v1/settings/models')+'?'+query;
    const data=await api(path);status.textContent='';
    if(conversationId===state.conversationID) paintConversationModel(data);
    const modelLabel=element('label',t("Модель")), model=element('select','','field');model.id='model-choice';model.setAttribute('aria-label',t("Модель"));modelLabel.append(model);page.content.append(modelLabel);
    const ref=m=>m?.model?JSON.stringify([m.provider||'chatgpt',m.model]):'';
    const modelRef=m=>JSON.stringify([m.provider||'chatgpt',m.id]);
    const lookup=key=>data.models.find(m=>modelRef(m)===key);
    const title=m=>m.name+((data.providers||[]).length>1?' · '+(data.providers.find(p=>p.id===m.provider)?.name||m.provider):'');
    if(inherits) { const o=element('option',t(conversationId?"Как у сотрудника · ":"Как на устройстве · ")+(lookup(ref(data.defaults))?.name||data.recommended?.name||data.defaults.model||t("Автоматически")));o.value='';model.append(o); }
    else if(data.recommended) { const o=element('option',t("Автоматически · ")+data.recommended.name);o.value='';model.append(o); }
    for(const m of data.models) { const o=element('option',title(m));o.value=modelRef(m);model.append(o); }
    if(data.selection.model&&!lookup(ref(data.selection))) {const o=element('option',data.selection.model+t(" · недоступна"));o.value=ref(data.selection);model.append(o);}
    model.value=ref(data.selection);
    const speedLabel=element('label',t("Скорость")), speed=element('select','','field');speed.id='model-speed';speed.setAttribute('aria-label',t("Скорость"));speedLabel.append(speed);page.content.append(speedLabel);
    const reasoningLabel=element('label',t("Обдумывание")), reasoning=element('select','','field');reasoning.id='model-reasoning';reasoning.setAttribute('aria-label',t("Обдумывание"));reasoningLabel.append(reasoning);page.content.append(reasoningLabel);
    const recommendation=element('p'),note=element('p');page.content.append(recommendation,note);
    let fallbacks=(data.fallbacks||[]).map(m=>({...m}));
    const reserves=!inherits&&Array.isArray(data.fallbacks)?element('div','','model-fallbacks'):null;
    if(reserves)page.content.append(reserves);
    let pending=false;
    const value=()=>{const [provider,id]=model.value?JSON.parse(model.value):[null,null];return {provider,model:id,serviceTier:!model.value&&inherits?null:speed.value,...(model.value||!inherits)&&reasoning.value?{reasoningEffort:reasoning.value}:{},...(reserves?{fallbacks}:{})};};
    const chosenModel=()=>model.value?lookup(model.value):inherits?(lookup(ref(data.defaults))||data.recommended):data.recommended;
    const save=element('button',t("Применить"),'primary');save.type='button';save.dataset.main='true';page.actions.append(save);arrange(page);
    save.onclick=async()=>{
      pending=true;save.disabled=true;page.error.textContent='';model.disabled=speed.disabled=reasoning.disabled=true;status.textContent=t("Сохраняем…");update();
      try {const result=await api(path,{method:'POST',body:JSON.stringify(value())});Object.assign(data,result); if(conversationId===state.conversationID) paintConversationModel(result); status.textContent=t("Сохранено. Применится со следующего поручения.");}
      catch(e){status.textContent=t("Не удалось сохранить.");page.report(e);}
      finally {pending=false;model.disabled=!data.canManage;update();}
    };
    function update(){
      speed.disabled=(!model.value&&inherits)||!data.canManage||pending;
      reasoning.disabled=speed.disabled;
      recommendation.textContent=!model.value&&!inherits&&data.recommended?(data.recommended.isDefault?t("Рекомендует OpenAI"):t("Модель по умолчанию")):'';
      note.textContent=speed.value&&speed.value!=='default'?t("Ускоренный режим может расходовать больше лимита аккаунта."):'';
      const chosen=chosenModel();
      const selected=value(),saved=data.selection;
      const unchanged=['provider','model','serviceTier','reasoningEffort'].every(k=>(selected[k]??null)===(saved[k]??null))&&(!reserves||JSON.stringify(fallbacks)===JSON.stringify(data.fallbacks));
      save.disabled=!data.canManage||pending||unchanged||!chosen||(!model.value&&inherits?false:!chosen.speeds.some(s=>s.id===speed.value)||(reasoning.value&&!(chosen.reasoningEfforts||[]).some(e=>e.id===reasoning.value)));
      if(reserves)renderReserves();
    }
    function renderReserves(){
      reserves.replaceChildren(element('strong',t("Резервные модели")),element('p',t("При исчерпании лимита — следующая по порядку. Когда лимит вернётся — снова основная. Ключи API оплачиваются отдельно."),'hint'));
      fallbacks.forEach((entry,i)=>{
        const line=element('div','','model-fallback-row'), m=lookup(ref(entry));
        line.append(element('span',(i+1)+'. '+(m?title(m):entry.model)));
        for(const [label,symbol,disabled,change] of [[t("Выше"),'↑',i===0,()=>{[fallbacks[i-1],fallbacks[i]]=[fallbacks[i],fallbacks[i-1]];}],[t("Ниже"),'↓',i===fallbacks.length-1,()=>{[fallbacks[i+1],fallbacks[i]]=[fallbacks[i],fallbacks[i+1]];}],[t("Удалить резерв"),'−',false,()=>fallbacks.splice(i,1)]]){
          const button=element('button',symbol,'secondary');button.type='button';button.setAttribute('aria-label',label+' '+(i+1));button.disabled=disabled||pending||!data.canManage;button.onclick=()=>{change();status.textContent='';update();};line.append(button);
        }
        reserves.append(line);
      });
      const add=element('select','','field');add.setAttribute('aria-label',t("Добавить резерв"));add.id='add-model-fallback';
      const placeholder=element('option',t("Добавить резерв"));placeholder.value='';add.append(placeholder);
      for(const m of data.models.filter(m=>modelRef(m)!==modelRef(chosenModel()||{})&&!fallbacks.some(f=>ref(f)===modelRef(m)))){const o=element('option',title(m));o.value=modelRef(m);add.append(o);}
      add.disabled=pending||!data.canManage||add.options.length===1;
      add.onchange=()=>{const m=lookup(add.value);if(m){fallbacks.push({provider:m.provider||'chatgpt',model:m.id,serviceTier:'default'});status.textContent='';update();}};
      reserves.append(add);
    }
    function speeds(preferred,preserve=false){
      const chosen=chosenModel();speed.replaceChildren();
      for(const s of chosen?.speeds||[]){const o=element('option',t(s.name));o.value=s.id;speed.append(o);}
      if(preserve&&preferred&&!(chosen?.speeds||[]).some(s=>s.id===preferred)){const o=element('option',preferred+t(" · недоступна"));o.value=preferred;speed.append(o);}
      speed.value=preserve&&preferred?preferred:(chosen?.speeds||[]).some(s=>s.id===preferred)?preferred:'default';
      const effort=preserve?(data.selection.reasoningEffort||(!model.value&&inherits?data.defaults.reasoningEffort:'')):!model.value&&inherits?data.defaults.reasoningEffort:reasoning.value;
      reasoning.replaceChildren();const automatic=element('option',t("Автоматически"));automatic.value='';reasoning.append(automatic);
      for(const e of chosen?.reasoningEfforts||[]){const o=element('option',t(e.name));o.value=e.id;reasoning.append(o);}
      if(preserve&&effort&&!(chosen?.reasoningEfforts||[]).some(e=>e.id===effort)){const o=element('option',effort+t(" · недоступна"));o.value=effort;reasoning.append(o);}
      reasoning.value=effort&&(preserve||(chosen?.reasoningEfforts||[]).some(e=>e.id===effort))?effort:'';
      reasoningLabel.hidden=!(chosen?.reasoningEfforts||[]).length&&!reasoning.value;
      speedLabel.hidden=(chosen?.speeds||[]).length<=1&&speed.value==='default';update();
    }
    speeds(data.selection.serviceTier||data.defaults.serviceTier,true);model.disabled=!data.canManage;
    model.onchange=()=>{status.textContent='';fallbacks=fallbacks.filter(m=>ref(m)!==modelRef(chosenModel()||{}));speeds(!model.value&&inherits?data.defaults.serviceTier:speed.value);};speed.onchange=reasoning.onchange=()=>{status.textContent='';update();};
  }catch(e){status.textContent='';page.report(e);action(page,t("Повторить"),()=>openModelSettings(agent,deviceId,conversationId));}
}

async function openSpeechSettings(deviceId) {
  const page=modalPage(t("Голос"),t("Для сотрудников и Telegram-бота на выбранном устройстве."));
  try {
    const control=await api('/v1/home');deviceId ||= control.home.nodeId;
    if(control.devices.length>1) {
      const label=element('label',t("Устройство")), device=element('select','','field');label.append(device);
      for(const item of control.devices){const option=element('option',item.name);option.value=item.id;device.append(option);}
      device.value=deviceId;device.onchange=()=>void openSpeechSettings(device.value);page.content.append(label);
    }
    const path='/v1/settings/speech?'+new URLSearchParams({deviceId});
    const data=await api(path);
    const providerLabel=element('label',t("Распознавание")), provider=element('select','','field');provider.id='speech-provider';providerLabel.append(provider);
    for(const [value,title] of [['local',t("На устройстве")],['elevenlabs','ElevenLabs']]){const option=element('option',title);option.value=value;provider.append(option);}
    provider.value=data.provider;provider.disabled=!data.canManage;page.content.append(providerLabel);
    const cloud=element('div');page.content.append(cloud);
    cloud.append(element('p',t("Аудио отправляется в ElevenLabs. Ключ хранится на устройстве сотрудника."),'hint'));
    const keyLabel=element('label',data.connected?t("Новый ключ ElevenLabs"):t("API-ключ ElevenLabs")), key=element('input','','field');
    key.type='password';key.autocomplete='new-password';key.id='speech-key';key.disabled=!data.canManage;keyLabel.append(key);cloud.append(keyLabel);
    if(data.connected)cloud.append(element('p',t("ElevenLabs подключён"),'hint'));
    let voice;
    if(data.connected&&data.voices.length){
      const label=element('label',t("Голос для озвучивания"));voice=element('select','','field');label.append(voice);voice.disabled=!data.canManage;
      for(const item of data.voices){const option=element('option',item.name);option.value=item.id;voice.append(option);}
      voice.value=data.voiceId;page.content.append(label,element('p',t("Сотрудник озвучит ответ, когда вы попросите. Используется ElevenLabs."),'hint'));
    }
    const local=element('p',t("На Mac используется OpenRamble, на сервере — встроенное распознавание. Аудио остаётся на устройстве."),'hint');page.content.append(local);
    const save=action(page,t("Применить"),async()=>{
      const body={provider:provider.value};if(key.value.trim())body.key=key.value.trim();if(voice&&voice.value!==data.voiceId)body.voiceId=voice.value;
      await api(path,{method:'POST',body:JSON.stringify(body)});key.value='';await openSpeechSettings(deviceId);
    },true);
    const update=()=>{cloud.hidden=provider.value!=='elevenlabs';local.hidden=!cloud.hidden;save.disabled=!data.canManage||(provider.value==='elevenlabs'&&!data.connected&&!key.value.trim())||(provider.value===data.provider&&!key.value.trim()&&(!voice||voice.value===data.voiceId));};
    provider.onchange=key.oninput=update;if(voice)voice.onchange=update;update();
    if(data.connected&&data.canManage)action(page,t("Удалить ключ ElevenLabs"),async()=>{await api(path,{method:'POST',body:JSON.stringify({removeKey:true})});await openSpeechSettings(deviceId);},'destructive');
  }catch(error){page.report(error);action(page,t("Повторить"),()=>openSpeechSettings(deviceId));}
}

async function openComputerSettings() {
  const page=modalPage(t("Управление компьютером"),t("Сотрудник работает с окнами приложений на своём Mac через официальный Computer Use в Codex."));
  const loading=element('p',t("Проверяем Computer Use…"));page.content.append(loading);
  const path='/v1/extensions/computer?conversationId='+encodeURIComponent(state.conversationID||'');
  try {
    const data=await api(path);loading.textContent='';
    if(data.configured) {
      page.content.append(element('p',t("Подключено через Codex. Доступ к нужным приложениям разрешается отдельно при первом поручении.")));
      if(state.owner)action(page,t("Отключить"),async()=>{await api(path,{method:'DELETE'});await openComputerSettings();},'danger');
    } else if(data.platform!=='darwin') {
      page.content.append(element('p',t("Окнами приложений можно управлять у сотрудника на Mac. На этом устройстве доступны команды, файлы и подключённые сервисы.")));
    } else if(data.available) {
      if(state.owner)action(page,t("Подключить Computer Use"),async()=>{await api(path,{method:'POST',body:JSON.stringify({conversationId:state.conversationID})});await openComputerSettings();},true);
    } else {
      page.content.append(element('p',t("На Mac сотрудника откройте ChatGPT и включите плагин Computer Use. Затем вернитесь сюда.")));
      const link=element('a',t("Как включить Computer Use"));link.href='https://learn.chatgpt.com/docs/computer-use';link.target='_blank';link.rel='noreferrer';page.content.append(link);
      action(page,t("Проверить снова"),openComputerSettings);
    }
  }catch(e){loading.textContent='';page.report(e);action(page,t("Повторить"),openComputerSettings);}
}

function languageField(page, afterChange) {
  const label=element('label',t('Language')), select=element('select','','field');
  select.setAttribute('aria-label',t('Language'));select.id='interface-language';
  for(const [code,name] of StrudelLocale.languages) { const option=element('option',name);option.value=code;select.append(option); }
  select.value=i18n.language;label.append(select);page.content.prepend(label);
  select.onchange=()=>{
    setInterfaceLanguage(select.value);
    renderAgents();renderMessages();paintHeader();renderImportedChats();
    afterChange();
  };
  return label;
}

function accountPlan(plan) {
  return ({free:'ChatGPT Free',go:'ChatGPT Go',plus:'ChatGPT Plus',pro:'ChatGPT Pro',promax:'ChatGPT Pro Max',prolite:'ChatGPT Pro Lite',team:'ChatGPT Business',business:'ChatGPT Business',self_serve_business_prolite:'ChatGPT Business',self_serve_business_usage_based:'ChatGPT Business',enterprise:'ChatGPT Enterprise',ent26:'ChatGPT Enterprise',enterprise_cbp_automation:'ChatGPT Enterprise',enterprise_cbp_usage_based:'ChatGPT Enterprise',edu:'ChatGPT Edu',edu_plus:'ChatGPT Edu',edu_pro:'ChatGPT Edu'})[plan]||'ChatGPT';
}
function accountCategory(plan) {
  if(['free','go','plus','pro','prolite','promax'].includes(plan))return t('Personal account');
  if(accountPlan(plan)!=='ChatGPT')return t('Workspace account');
  return '';
}
