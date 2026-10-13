const agentKinds = ['coil','fold','knot','curl','wave','pillow'];
const agentKindNames = () => [t("Завиток"),t("Конвертик"),t("Узелок"),t("Рогалик"),t("Волна"),t("Подушечка")];
const agentTones = () => [t("Абрикос"),t("Мёд"),t("Фисташка"),t("Мята"),t("Небо"),t("Черника"),t("Сирень"),t("Малина")];
const agentAngles = [0,32,72,125,180,215,255,315];
function agentAppearance(profile) {
  const value=profile.appearance;
  if(value?.version===1 && agentKinds.includes(value.kind) && Number.isInteger(value.tone) && value.tone>=0 && value.tone<8) return {...value};
  let hash=2166136261;
  for(const byte of new TextEncoder().encode(profile.id)) hash=Math.imul(hash^byte,16777619)>>>0;
  return {version:1,kind:agentKinds[hash%6],tone:Math.floor(hash/6)%8};
}
/* The main assistant (no appearance) is the brand bun; employees are one of six shapes in one of eight tones. */
function characterImage(appearance, size=32) {
  const img=document.createElement('img'); img.src='/characters/'+(appearance?appearance.kind:'main')+'.png';
  img.alt=''; img.width=img.height=size; img.className='character'; img.draggable=false; img.decoding='async';
  if(appearance) img.style.setProperty('--tone',agentAngles[appearance.tone]+'deg');
  return img;
}
function appearanceEditor(initial) {
  let selected={...initial};
  const root=document.createElement('section'); root.className='appearance-editor';
  root.setAttribute('aria-label',t("Образ сотрудника"));
  const render=()=>{
    root.replaceChildren();
    const heading=document.createElement('div'); heading.className='appearance-heading';
    const name=document.createElement('strong'); name.textContent=t("Образ");
    const shuffle=document.createElement('button'); shuffle.type='button'; shuffle.className='secondary'; shuffle.textContent=t("Другой"); shuffle.setAttribute('aria-label',t("Случайный образ"));
    shuffle.onclick=()=>{ const random=crypto.getRandomValues(new Uint32Array(1))[0]; const n=(agentKinds.indexOf(selected.kind)*8+selected.tone+1+random%47)%48; selected={version:1,kind:agentKinds[Math.floor(n/8)],tone:n%8}; render();root.querySelector('.appearance-heading button').focus(); };
    heading.append(name,shuffle); root.append(heading);
    const kinds=document.createElement('div'); kinds.className='character-choices'; kinds.setAttribute('role','group'); kinds.setAttribute('aria-label',t("Персонаж"));
    agentKinds.forEach((kind,index)=>{
      const button=document.createElement('button'); button.type='button'; button.className='character-choice'; button.setAttribute('aria-label',agentKindNames()[index]);button.setAttribute('aria-pressed',String(selected.kind===kind));
      button.append(characterImage({...selected,kind},48));button.onclick=()=>{selected.kind=kind;render();root.querySelector(`[aria-label="${agentKindNames()[index]}"]`).focus();}; kinds.append(button);
    }); root.append(kinds);
    const tones=document.createElement('div'); tones.className='tone-choices'; tones.setAttribute('role','group'); tones.setAttribute('aria-label',t("Цвет"));
    agentTones().forEach((label,tone)=>{
      const button=document.createElement('button'); button.type='button'; button.className='tone-choice'; button.setAttribute('aria-label',label);button.setAttribute('aria-pressed',String(selected.tone===tone));
      const swatch=document.createElement('span');swatch.className='tone-swatch'; swatch.style.setProperty('--tone',agentAngles[tone]+'deg');if(selected.tone===tone) swatch.append(icon('check'));
      button.append(swatch);button.onclick=()=>{selected.tone=tone;render();root.querySelector(`[aria-label="${label}"]`).focus();};tones.append(button);
    });root.append(tones);
  };render();return {root,value:()=>({...selected})};
}
