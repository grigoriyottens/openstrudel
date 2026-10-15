import type { Store } from './store.js';
import { HomeError } from './home.js';
import { chatgptSignedIn } from './account.js';
import { providerConnected, providerConnectedAt, providerInfo, providerInfos, providerModels, providerNotConnected, subscriptionModels } from './providers.js';

/** `provider` is null only with a null model: as on the device, or automatic for the device itself. */
export type ModelSelection = { provider: string | null; model: string | null; serviceTier: string | null };
export type ModelChoice = { id: string; name: string; description: string; isDefault: boolean; defaultReasoningEffort?: string; speeds: Array<{ id: string; name: string; description: string }>; provider?: string };
const defaultsKey = 'models.defaults';

/** Capabilities come from the selected account's native Codex catalog. */
export function normalizeModels(rows: any[], requirements: any, provider = 'chatgpt'): ModelChoice[] {
  const features = requirements?.featureRequirements ?? {};
  return rows.filter(m => !m.hidden && typeof m.model === 'string').map(m => {
    const tiers = Array.isArray(m.serviceTiers) ? m.serviceTiers : (m.additionalSpeedTiers ?? []).includes('fast') ? [{id:'priority',name:'Fast',description:''}] : [];
    return { id:m.model, name:m.displayName || m.model, description:m.description || '', isDefault:m.isDefault === true, defaultReasoningEffort:m.defaultReasoningEffort || 'medium',
      speeds:[{id:'default',name:'Обычная',description:''}, ...tiers.filter((s:any) => typeof s.id === 'string' && s.id !== 'default' && typeof s.name === 'string'
        && (requirements?.supportsIndependentSpeedModes === true ? (/ultra/i.test(s.id + s.name) ? features.ultrafast_mode !== false : features.fast_mode !== false) : features.fast_mode !== false))
        .map((s:any)=>({id:s.id,name:s.name,description:s.description || ''}))], provider };
  });
}
export function recommendedModel(models: ModelChoice[]): ModelChoice {
  return models.find(m=>m.isDefault) ?? {
    ...(models.find(m=>m.id === 'gpt-6.1-sol') ?? {id:'gpt-6.1-sol',name:'GPT-6.1 Sol',description:'',speeds:[{id:'default',name:'Обычная',description:''}]}),
    isDefault:false,defaultReasoningEffort:'medium',
  };
}
/** A model stored before providers existed is a ChatGPT model. */
export function readModelSelection(store: Store, agent?: string): ModelSelection {
  const stored = (value: any): ModelSelection => ({provider:value.provider ?? (value.model ? 'chatgpt' : null),model:value.model ?? null,serviceTier:value.serviceTier ?? null});
  if (!agent) return stored(JSON.parse(store.getSetting(defaultsKey) ?? JSON.stringify({model:process.env.OPENSTRUDEL_CODEX_MODEL ?? null,serviceTier:'default'})));
  if (agent === 'main') return stored(JSON.parse(store.getSetting('models.main') ?? '{"model":null,"serviceTier":null}'));
  const profile = store.getProfile(agent);
  if (!profile) throw new HomeError('Сотрудник не найден.',404);
  return stored({...profile,serviceTier:profile.serviceTier ?? (profile.model ? 'default' : null)});
}
/** ChatGPT when signed in, otherwise the key or subscription connected first, so adding one changes nothing. Quota never switches it. */
export function automaticProvider(store: Store): string {
  return chatgptSignedIn(store) ? 'chatgpt' : providerInfos().filter(p => providerConnected(store,p.id)).sort((a,b) => providerConnectedAt(store,a.id) - providerConnectedAt(store,b.id))[0]?.id ?? 'chatgpt';
}
/** Employee → device default → automatic. A Codex catalog fills the model only when one is given. */
export function resolveModelSelection(store: Store, agent?: string, models?: ModelChoice[]): ModelSelection {
  const selection = readModelSelection(store,agent);
  const resolved = selection.model ? selection : readModelSelection(store);
  if (resolved.model) return resolved;
  // A subscription's catalog is the one its agent last reported; without one, the agent runs its own default.
  const provider = automaticProvider(store), info = providerInfo(provider), reported = info?.engine === 'acp' ? subscriptionModels(store,provider) : undefined;
  const registry = reported ?? (info?.models.length ? providerModels(info) : undefined), catalog = registry ?? models?.filter(m => m.provider === provider);
  return {provider,model:catalog && (catalog.length || !reported) ? recommendedModel(catalog).id : null,serviceTier:registry ? 'default' : resolved.serviceTier};
}
/** `models` is one provider's catalog. */
export function validateModelSelection(value: Pick<ModelSelection, 'model' | 'serviceTier'>, models: ModelChoice[]) {
  const model = value.model ? models.find(m=>m.id === value.model) : recommendedModel(models);
  if (!model) throw new HomeError('Эта модель недоступна для аккаунта. Выберите другую в настройках модели.',409);
  if (!model.speeds.some(s=>s.id === value.serviceTier)) throw new HomeError('Эта скорость недоступна для выбранной модели. Выберите другую в настройках.',409);
}
/** A saved choice must run here: its provider is connected and offers the model and speed. */
export function checkModelSelection(store: Store, value: ModelSelection, models: ModelChoice[]) {
  const provider = value.model ? value.provider! : automaticProvider(store);
  if (provider !== 'chatgpt' && !providerConnected(store,provider)) throw providerNotConnected(provider);
  validateModelSelection(value,models.filter(m=>m.provider === provider));
}
/** Older apps send no provider: their models are ChatGPT models. */
export function parseModelSelection(value: any, allowInherit: boolean): ModelSelection {
  if (allowInherit && value.model === null && value.serviceTier === null && value.provider == null) return {provider:null,model:null,serviceTier:null};
  const automatic = !allowInherit && value.model === null && value.provider == null;
  const provider = automatic ? null : value.provider ?? 'chatgpt';
  if ((!automatic && (typeof value.model !== 'string' || !value.model || value.model.length > 160 || (provider !== 'chatgpt' && !providerInfo(provider)))) || typeof value.serviceTier !== 'string' || !value.serviceTier || value.serviceTier.length > 80) throw new HomeError('Выберите модель и скорость.');
  return {provider,model:value.model,serviceTier:value.serviceTier};
}
export function saveModelSelection(store: Store, value: ModelSelection, agent?: string) {
  if (!agent || agent === 'main') store.setSetting(agent ? 'models.main' : defaultsKey,JSON.stringify(value));
  else {
    if (!store.getProfile(agent)) throw new HomeError('Сотрудник не найден.',404);
    store.db.prepare('UPDATE employee_profiles SET provider=?,model=?,service_tier=? WHERE id=?').run(value.provider,value.model,value.serviceTier,agent);
  }
}
