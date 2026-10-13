function element(tag, text, className) { const e = document.createElement(tag); if (text) e.textContent = text; if (className) e.className = className; return e; }
/* A modal page: title, content, then a bottom bar with Cancel first and one main action last.
   close: 'done' (default), 'cancel', or false when the page owns its buttons or must not be dismissed.
   A page reached from the Settings list leads with a way back to it; a locked page is the whole screen. */
function modalPage(title, description, { close: closeKind = 'done', locked = false } = {}) {
  const box = element('div', '', 'page');
  if (state.fromSettings && !locked) { const back = element('button', '', 'back'); back.type = 'button'; back.append(icon('back', true), element('span', t("Настройки"))); back.onclick = () => void openHomeSettings(); box.append(back); }
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
   'danger' for a destructive secondary action. A new main action demotes the previous one. */
function action(page, title, work, kind = false) {
  const main = kind === true || kind === 'destructive';
  const button = element('button', title, kind === true ? 'primary' : kind === 'destructive' || kind === 'danger' ? 'destructive' : 'secondary');
  button.type = 'button';
  if (main) { for (const other of page.actions.querySelectorAll('[data-main="true"]')) { delete other.dataset.main; if (other.classList.contains('primary')) other.className = 'secondary'; } button.dataset.main = 'true'; }
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
    state.csrf=session.csrf; state.owner=session.owner; state.authenticated=true; closeModal(); await refresh();
    restoreDraft();
    const transfer = JSON.parse(localStorage.getItem('openstrudel.transfer') || 'null');
    if (transfer) await watchTransfer(transfer);
    state.refreshTimer=setInterval(()=>{ if(!document.hidden && !state.loading) void refresh(); },5000);
  } catch(e) {
    const page=modalPage(t("Подключитесь к своей команде"),t("Откройте приглашение для браузера из настроек OpenStrudel на Mac или сервере с вашими сотрудниками."),{close:false,locked:true});
    page.box.prepend(characterImage(null,96));
    const input=field(page.content,t("Ссылка с приглашением")); input.value=state.invitationDraft||''; input.type='url'; input.autocomplete='off';
    const language=languageField(page,()=>{state.invitationDraft=input.value;void bootstrapWeb();});
    language.className='language-line'; page.box.append(language);
    if(key) page.report(e);
    action(page,t("Подключиться"),async()=>{
      const url=new URL(input.value.trim());
      if(url.origin!==location.origin) throw new Error(t("Это приглашение для другого устройства. Откройте его адрес в браузере."));
      const invite=new URLSearchParams(url.hash.slice(1)).get('invite'); if(!invite) throw new Error(t("В ссылке нет приглашения."));
      const session=await api('/auth/session',{method:'POST',body:JSON.stringify({key:invite})});
      state.csrf=session.csrf; state.owner=session.owner; closeModal(); await bootstrapWeb();
    },true);
    input.focus();
  }
}
window.addEventListener('hashchange',()=>{ if(new URLSearchParams(location.hash.slice(1)).has('invite')) void bootstrapWeb(); });
async function openHomeSettings() {
  state.fromSettings=false;
  const page=modalPage(t("Настройки"),t("Сотрудники и переписка находятся на этом устройстве."));
  languageField(page,()=>void openHomeSettings());
  const entries=state.owner ? [[t("Устройства"),openDevices],[t("Настройки сотрудника"),openCurrentAgent],[t("Аккаунты и лимиты"),openAccounts],[t("Модель и скорость"),()=>openModelSettings()],[t("Резервная копия"),openSettings],['Telegram',openTelegramSettings]] : [[t("Аккаунты и лимиты"),openAccounts]];
  const list=group(page.content);
  for(const [label,fn] of entries) row(list,label,()=>{state.fromSettings=true;return fn();});
  if(state.hostingOrigin) {
    const hosting=new URL(state.hostingOrigin);
    if(hosting.protocol==='https:'||hosting.protocol==='http:') row(list,t("Серверы: создание и продление"),null,{href:hosting.href});
  }
  row(group(page.content),t("Выйти на этом устройстве"),openDeviceSignOut,{className:'destructive-row'});
}
async function openDevices() {
  const page=modalPage(t("Устройства"),t("Сотрудники остаются на устройстве, где созданы. Для работы с несколькими устройствами откройте приложение OpenStrudel."));
  try {
    const data=await api('/v1/devices'); state.devices=data.devices;
    if(JSON.parse(localStorage.getItem(controlsKey())||'[]').length) action(page,t("Проверить сохранённые действия"),()=>checkControls(page));
    const control=await api('/v1/home');
    const list=group(page.content);
    for(const device of data.devices) row(list,device.name,null,{detail:t("{0} · Сотрудников: {1}",device.online?t("На связи"):t("Не на связи"),device.agents)});
    if(control.operations?.length) { const moves=group(page.content); for(const operation of control.operations) row(moves,t("Проверить перенос сотрудника"),()=>watchAgentMove(operation.id)); }
    if(state.owner) {
      action(page,t("Открыть на другом устройстве"),async()=>{
        const invite=await api('/v1/mobile/pairing',{method:'POST',body:JSON.stringify({owner:true})});
        const next=modalPage(t("Подключение устройства"),t("На другом Mac откройте Настройки → Устройства → Подключить устройство и вставьте эту ссылку. Она действует пять минут."));
        const text=field(next.content,t("Личная ссылка подключения"),'password'); text.value=invite.url; text.readOnly=true;
        action(next,t("Скопировать ссылку"),async()=>{await navigator.clipboard.writeText(invite.url);next.error.textContent=t("Ссылка скопирована. Продолжите на другом устройстве.");},true);
      },true);
    }
  } catch(e) { page.report(e); }
}
async function openCurrentAgent() {
  const agent=state.selected||'main', profile=state.profiles.find(p=>p.id===agent), name=profile?.name||'OpenStrudel';
  const page=modalPage(name,'',{close:'cancel'});
  const list=group(page.content);
  row(list,t("Модель и скорость"),()=>openModelSettings(agent));
  row(list,t("Управление компьютером"),openComputerSettings);
  let editor=null, select=null, initialAccount='';
  if(profile && state.appearanceVersion===1) { editor=appearanceEditor(agentAppearance(profile)); page.content.append(editor.root); }
  action(page,t("Сохранить"),async()=>{
    if(editor && JSON.stringify(editor.value())!==JSON.stringify(agentAppearance(profile))) {
      const result=await api('/v1/profiles/'+encodeURIComponent(profile.id),{method:'PATCH',body:JSON.stringify({name:profile.name,instructions:profile.instructions,appearance:editor.value()})});
      if(JSON.stringify(result.profile?.appearance)!==JSON.stringify(editor.value())) throw new Error(t("Обновите OpenStrudel на устройстве этого сотрудника, чтобы сохранить образ."));
    }
    if(select && select.value!==initialAccount) await api('/v1/agents/'+agent+'/accounts',{method:'POST',body:JSON.stringify({accountIds:select.value?[select.value]:null})});
    closeModal();await refresh();
  },true);
  try {
    const control=await api('/v1/home'), deviceId=profile?.deviceId||control.home.mainNodeId;
    const device=control.devices.find(d=>d.id===deviceId);
    page.content.append(element('p',t("Работает на «{0}».",device?.name||t("вашем устройстве"))));
    const data=await api('/v1/accounts?deviceId='+encodeURIComponent(deviceId)), policy=await api('/v1/agents/'+agent+'/accounts');
    const label=element('label',t("Аккаунт OpenAI")); select=element('select','','field'); label.append(select); page.content.append(label);
    page.content.append(element('p',t("Настройки изменят новые поручения. Уже начатая работа продолжится с прежним аккаунтом."),'hint'));
    const defaultOption=element('option',t("По умолчанию")); defaultOption.value=''; select.append(defaultOption);
    for(const account of data.accounts) { const option=element('option',(account.account.email||account.name)+' · '+accountPlan(account.account.planType)); option.value=account.id; select.append(option); }
    if(policy.accountIds?.length===1) select.value=policy.accountIds[0];
    else if(policy.accountIds?.length>1) page.content.append(element('p',t("Выбран отдельный порядок аккаунтов. Новый выбор заменит его.")));
    initialAccount=select.value;
  } catch(e) { page.report(e); }
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
          const edit=modalPage(t('Rename account'),t('Choose a name you recognise. Your OpenAI account stays the same.'),{close:'cancel'});
          const input=field(edit.content,t('Название аккаунта'));input.value=title;input.maxLength=80;
          const save=action(edit,t('Сохранить'),async()=>{await api(`/v1/accounts/${entry.id}`+suffix,{method:'POST',body:JSON.stringify({name:input.value.trim()})});await openAccounts(deviceId);},true);
          input.oninput=()=>{save.disabled=!input.value.trim();};input.focus();input.select();
        };more.append(rename);
        const login=element('button',entry.account.connected?t("Войти заново"):t("Войти в OpenAI"),'secondary');
        login.onclick=()=>void startAccountLogin(entry.id,deviceId);(entry.account.connected?more:card).append(login);
        if(i>0&&entry.account.connected) { const use=element('button',t("Использовать первым"),'secondary'); use.onclick=async()=>{try{await api(`/v1/accounts/${entry.id}/priority`+suffix,{method:'POST',body:'{}'}); await openAccounts(deviceId);}catch(e){page.report(e);}}; more.append(use); }
        card.append(more);
      }
      list.append(card);
    }
    action(page,t("Обновить остатки"),()=>openAccounts(deviceId,true));
    if(data.canManage) action(page,t("Добавить аккаунт"),async()=>{ const entry=await api('/v1/accounts'+suffix,{method:'POST',body:JSON.stringify({name:t("Аккаунт")})}); await startAccountLogin(entry.id,deviceId); });
  } catch(e) { page.report(e); action(page,t("Повторить"),()=>openAccounts(deviceId)); }
  finally { loading.remove(); }
}
async function startAccountLogin(accountId,deviceId) {
  const page=modalPage(t("Вход в OpenAI"),t("Войдите в свой аккаунт на сайте OpenAI и подтвердите подключение этого устройства."));
  const base=`/v1/accounts/${encodeURIComponent(accountId)}/login`, suffix='?deviceId='+encodeURIComponent(deviceId);
  try {
    const login=await api(base+suffix,{method:'POST',body:'{}'});
    const code=element('p',login.userCode,'code-display'); code.dir='ltr'; page.content.append(code);
    const link=element('a',t("Открыть OpenAI")); const url=new URL(login.verificationUrl); if(url.protocol!=='https:' || url.hostname!=='auth.openai.com') throw new Error(t("OpenAI вернул неизвестный адрес входа."));
    link.href=url.href; link.target='_blank'; link.rel='noopener noreferrer'; page.content.append(link);
    action(page,t("Проверить вход"),async()=>{ const result=await api(base+'/'+encodeURIComponent(login.loginId)+suffix); if(result.status==='completed') await openAccounts(deviceId); else if(result.status==='failed'||result.status==='canceled') throw new Error(result.error || t("Вход отменён. Начните снова.")); else page.error.textContent=t("Завершите вход на сайте OpenAI."); },true);
    action(page,t("Отменить вход"),async()=>{await api(base+'/'+encodeURIComponent(login.loginId)+suffix,{method:'DELETE'}); await openAccounts(deviceId);},'danger');
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
    const button=row(list,profile?.name||'OpenStrudel',async()=>{closeModal();try{await selectAgent(profile?.id||null);}catch(e){notify(e.message);}},{avatar,detail:isOffline(profile)?t("Не на связи"):profile?previewLine(profile.preview)||profile.purpose:t("Помощник для ваших задач"),className:'agent-row'+(current?' current':'')});
    if(current) button.setAttribute('aria-current','page');
  }
  // Symbols sit in the avatar column so every title above and below starts on one edge.
  const symbol=name=>{const box=element('span','','avatar symbol');box.append(icon(name));return box;};
  const more=group(page.content);
  row(more,t("Настройки"),openHomeSettings,{avatar:symbol('gear')});
  row(more,t("Новый сотрудник"),openCreateAgent,{avatar:symbol('plus')});
}
async function sendDraft(event) {
  event.preventDefault(); const text=$('draft').value.trim(); if(!text||state.loading) return;
  let draft; try { draft = saveDraft(); } catch(e) { notify(e.message); return; }
  $('draft').value=''; syncDraft();
  await deliver({...draft,profile:state.selected||null,conversationId:state.chat||null});
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
    const result=await api('/v1/messages?async=true',{method:'POST',body:JSON.stringify({...draft,channel:'api',externalChatId:'home'})});
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
function draftKey() { return 'openstrudel.draft.' + (state.homeId || location.origin) + '.' + (state.chat || state.selected || 'main'); }
function saveDraft() {
  const text=$('draft').value;
  const previous=JSON.parse(localStorage.getItem(draftKey()) || 'null');
  const draft=previous?.text===text ? previous : { text, profile:state.selected, conversationId:state.chat, externalId:crypto.randomUUID() };
  try { localStorage.setItem(draftKey(),JSON.stringify(draft)); } catch { throw new Error(t("Не удалось сохранить черновик в браузере. Освободите место перед отправкой.")); }
  return draft;
}
function restoreDraft() {
  const draft=JSON.parse(localStorage.getItem(draftKey()) || 'null'); $('draft').value=draft?.text || '';
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
  if($('draft').value.trim()) page.content.append(element('p',t("Черновик останется в этом браузере для повторного подключения к этой команде.")));
  action(page,t("Выйти"),async()=>{ saveDraft(); await api('/auth/logout',{method:'POST'}); clearInterval(state.refreshTimer); location.reload(); },'destructive');
  if(state.owner && state.archiveVersion===1) action(page,t("Сначала сохранить копию…"),openSettings);
}

async function openModelSettings(agent, deviceId) {
  const page=modalPage(t("Модель и скорость"),agent?t("Для этого сотрудника. Начатая работа продолжится с прежними настройками."):t("По умолчанию для сотрудников устройства. Можно выбрать другую модель в настройках сотрудника."));
  const status=element('p',t("Получаем доступные модели…"));status.setAttribute('role','status');page.content.append(status);
  try {
    const control=await api('/v1/home');
    if(!agent) {
      const label=element('label',t("Устройство")), device=element('select','','field');label.append(device);
      for(const item of control.devices) { const o=element('option',item.name+(item.online?'':t(" · нет связи")));o.value=item.id;device.append(o); }
      deviceId ||= control.home.nodeId; device.value=deviceId;
      device.onchange=()=>void openModelSettings(undefined,device.value);page.content.prepend(label);
    }
    const query=new URLSearchParams();if(agent)query.set('agentId',agent);if(deviceId)query.set('deviceId',deviceId);
    const path='/v1/settings/models?'+query;
    const data=await api(path);status.textContent='';
    const modelLabel=element('label',t("Модель")), model=element('select','','field');model.id='model-choice';model.setAttribute('aria-label',t("Модель"));modelLabel.append(model);page.content.append(modelLabel);
    if(agent) { const o=element('option',t("Как на устройстве · ")+(data.models.find(m=>m.id===data.defaults.model)?.name||data.defaults.model));o.value='';model.append(o); }
    else if(data.recommended) { const o=element('option',t("Автоматически · ")+data.recommended.name);o.value='';model.append(o); }
    for(const m of data.models) { const o=element('option',m.name);o.value=m.id;model.append(o); }
    if(data.selection.model&&!data.models.some(m=>m.id===data.selection.model)) {const o=element('option',data.selection.model+t(" · недоступна"));o.value=data.selection.model;model.append(o);}
    model.value=data.selection.model||'';
    const speedLabel=element('label',t("Скорость")), speed=element('select','','field');speed.id='model-speed';speed.setAttribute('aria-label',t("Скорость"));speedLabel.append(speed);page.content.append(speedLabel);
    const recommendation=element('p'),note=element('p');page.content.append(recommendation,note);
    let pending=false;
    const value=()=>({model:model.value||null,serviceTier:!model.value&&agent?null:speed.value});
    const chosenModel=()=>!model.value&&!agent?data.recommended:(data.models.find(m=>m.id===(model.value||data.defaults.model))||(data.recommended?.id===(model.value||data.defaults.model)?data.recommended:null));
    const save=element('button',t("Применить"),'primary');save.type='button';save.dataset.main='true';page.actions.append(save);arrange(page);
    save.onclick=async()=>{
      pending=true;save.disabled=true;page.error.textContent='';model.disabled=speed.disabled=true;status.textContent=t("Сохраняем…");
      try {const result=await api(path,{method:'POST',body:JSON.stringify(value())});data.selection=result.selection;status.textContent=t("Сохранено. Применится со следующего поручения.");}
      catch(e){status.textContent=t("Не удалось сохранить.");page.report(e);}
      finally {pending=false;model.disabled=!data.canManage;update();}
    };
    function update(){
      speed.disabled=(!model.value&&Boolean(agent))||!data.canManage||pending;
      recommendation.textContent=!model.value&&!agent&&data.recommended?(data.recommended.isDefault?t("Рекомендует OpenAI"):t("Модель по умолчанию"))+' · '+(data.recommended.defaultReasoningEffort||'medium').replace(/^./,c=>c.toUpperCase()):'';
      note.textContent=speed.value&&speed.value!=='default'?t("Ускоренный режим может расходовать больше лимита аккаунта."):'';
      const chosen=chosenModel();
      save.disabled=!data.canManage||pending||JSON.stringify(value())===JSON.stringify(data.selection)||!chosen||(!model.value&&agent?false:!chosen.speeds.some(s=>s.id===speed.value));
    }
    function speeds(preferred,preserve=false){
      const chosen=chosenModel();speed.replaceChildren();
      for(const s of chosen?.speeds||[]){const o=element('option',t(s.name));o.value=s.id;speed.append(o);}
      if(preserve&&preferred&&!(chosen?.speeds||[]).some(s=>s.id===preferred)){const o=element('option',preferred+t(" · недоступна"));o.value=preferred;speed.append(o);}
      speed.value=preserve&&preferred?preferred:(chosen?.speeds||[]).some(s=>s.id===preferred)?preferred:'default';update();
    }
    speeds(data.selection.serviceTier||data.defaults.serviceTier,true);model.disabled=!data.canManage;
    model.onchange=()=>{status.textContent='';speeds(!model.value&&agent?data.defaults.serviceTier:speed.value);};speed.onchange=()=>{status.textContent='';update();};
  }catch(e){status.textContent='';page.report(e);action(page,t("Повторить"),()=>openModelSettings(agent,deviceId));}
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
  return ({free:'ChatGPT Free',go:'ChatGPT Go',plus:'ChatGPT Plus',pro:'ChatGPT Pro',prolite:'ChatGPT Pro Lite',team:'ChatGPT Business',business:'ChatGPT Business',self_serve_business_prolite:'ChatGPT Business',self_serve_business_usage_based:'ChatGPT Business',enterprise:'ChatGPT Enterprise',ent26:'ChatGPT Enterprise',enterprise_cbp_automation:'ChatGPT Enterprise',enterprise_cbp_usage_based:'ChatGPT Enterprise',edu:'ChatGPT Edu',edu_plus:'ChatGPT Edu',edu_pro:'ChatGPT Edu'})[plan]||'ChatGPT';
}
function accountCategory(plan) {
  if(['free','go','plus','pro','prolite'].includes(plan))return t('Personal account');
  if(accountPlan(plan)!=='ChatGPT')return t('Workspace account');
  return '';
}
