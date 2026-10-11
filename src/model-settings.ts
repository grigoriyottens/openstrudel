import type { Store } from './store.js';
import { HomeError } from './home.js';

export type ModelSelection = { model: string | null; serviceTier: string | null };
export type ModelChoice = { id: string; name: string; description: string; isDefault: boolean; defaultReasoningEffort?: string; speeds: Array<{ id: string; name: string; description: string }> };
const defaultsKey = 'models.defaults';

/** Capabilities come from the selected account's native Codex catalog. */
export function normalizeModels(rows: any[], requirements: any): ModelChoice[] {
  const features = requirements?.featureRequirements ?? {};
  return rows.filter(m => !m.hidden && typeof m.model === 'string').map(m => {
    const tiers = Array.isArray(m.serviceTiers) ? m.serviceTiers : (m.additionalSpeedTiers ?? []).includes('fast') ? [{id:'priority',name:'Fast',description:''}] : [];
    return { id:m.model, name:m.displayName || m.model, description:m.description || '', isDefault:m.isDefault === true, defaultReasoningEffort:m.defaultReasoningEffort || 'medium',
      speeds:[{id:'default',name:'Обычная',description:''}, ...tiers.filter((s:any) => typeof s.id === 'string' && s.id !== 'default' && typeof s.name === 'string'
        && (requirements?.supportsIndependentSpeedModes === true ? (/ultra/i.test(s.id + s.name) ? features.ultrafast_mode !== false : features.fast_mode !== false) : features.fast_mode !== false))
        .map((s:any)=>({id:s.id,name:s.name,description:s.description || ''}))] };
  });
}
export function recommendedModel(models: ModelChoice[]): ModelChoice {
  return models.find(m=>m.isDefault) ?? {
    ...(models.find(m=>m.id === 'gpt-6.1-sol') ?? {id:'gpt-6.1-sol',name:'GPT-6.1 Sol',description:'',speeds:[{id:'default',name:'Обычная',description:''}]}),
    isDefault:false,defaultReasoningEffort:'medium',
  };
}
export function readModelSelection(store: Store, agent?: string): ModelSelection {
  if (!agent) return JSON.parse(store.getSetting(defaultsKey) ?? JSON.stringify({model:process.env.OPENSTRUDEL_CODEX_MODEL ?? null,serviceTier:'default'}));
  if (agent === 'main') return JSON.parse(store.getSetting('models.main') ?? '{"model":null,"serviceTier":null}');
  const profile = store.getProfile(agent);
  if (!profile) throw new HomeError('Сотрудник не найден.',404);
  return {model:profile.model,serviceTier:profile.serviceTier ?? (profile.model ? 'default' : null)};
}
export function resolveModelSelection(store: Store, agent?: string, models?: ModelChoice[]): ModelSelection {
  const selection = readModelSelection(store,agent);
  const resolved = selection.model ? selection : readModelSelection(store);
  return models && !resolved.model ? {...resolved,model:recommendedModel(models).id} : resolved;
}
export function validateModelSelection(value: ModelSelection, models: ModelChoice[]) {
  const model = value.model ? models.find(m=>m.id === value.model) : recommendedModel(models);
  if (!model) throw new HomeError('Эта модель недоступна для аккаунта. Выберите другую в настройках модели.',409);
  if (!model.speeds.some(s=>s.id === value.serviceTier)) throw new HomeError('Эта скорость недоступна для выбранной модели. Выберите другую в настройках.',409);
}
export function parseModelSelection(value: any, allowInherit: boolean): ModelSelection {
  if (allowInherit && value.model === null && value.serviceTier === null) return {model:null,serviceTier:null};
  const automatic = !allowInherit && value.model === null;
  if ((!automatic && (typeof value.model !== 'string' || !value.model || value.model.length > 160)) || typeof value.serviceTier !== 'string' || !value.serviceTier || value.serviceTier.length > 80) throw new HomeError('Выберите модель и скорость.');
  return {model:value.model,serviceTier:value.serviceTier};
}
export function saveModelSelection(store: Store, value: ModelSelection, agent?: string) {
  if (!agent || agent === 'main') store.setSetting(agent ? 'models.main' : defaultsKey,JSON.stringify(value));
  else {
    if (!store.getProfile(agent)) throw new HomeError('Сотрудник не найден.',404);
    store.db.prepare('UPDATE employee_profiles SET model=?,service_tier=? WHERE id=?').run(value.model,value.serviceTier,agent);
  }
}
