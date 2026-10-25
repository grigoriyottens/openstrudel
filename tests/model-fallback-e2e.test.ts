import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it, vi } from "vitest";
import { OpenStrudelRuntime } from "../src/runtime.js";
import { saveModelSelection } from "../src/model-settings.js";
import { mockAnthropic } from "./fixtures/mock-anthropic.js";
import { mockResponses } from "./fixtures/mock-responses.js";

it("uses the real reserve engine, skips the exhausted provider, then resumes its own history after recovery", async () => {
  let exhausted = true;
  const preferred = await mockAnthropic(() => exhausted ? {status:429,type:"rate_limit_error",message:"usage limit reached"} : {text:"primary recovered"});
  const reserve = await mockResponses("reserve answered");
  const root = mkdtempSync(join(tmpdir(),"openstrudel-fallback-e2e-"));
  vi.stubEnv("OPENSTRUDEL_CODEX_MODE","");
  vi.stubEnv("OPENSTRUDEL_PROVIDER_ANTHROPIC_BASE_URL",preferred.url);
  vi.stubEnv("OPENSTRUDEL_PROVIDER_XAI_BASE_URL",reserve.url);
  const runtime = new OpenStrudelRuntime({rootDirectory:root,dbPath:join(root,".data/home.sqlite"),startTelegram:false,apiToken:"e2e"});
  try {
    runtime.store.setSetting("providers.anthropic.key","test-anthropic");
    runtime.store.setSetting("providers.xai.key","test-xai");
    saveModelSelection(runtime.store,{provider:"anthropic",model:"claude-opus-5-5",serviceTier:"default"});
    runtime.store.setSetting("models.fallbacks",JSON.stringify([{provider:"xai",model:"grok-4.7",serviceTier:"default"}]));
    const send = (text:string) => runtime.messages.handle({channel:"api",externalChatId:"home",text});
    expect((await send("remember blue")).text).toBe("reserve answered");
    const refusals = preferred.requests.length;
    expect((await send("remember green")).text).toBe("reserve answered");
    expect(preferred.requests).toHaveLength(refusals);
    exhausted=false;
    const now=Date.now();vi.spyOn(Date,"now").mockReturnValue(now+61_000);
    expect((await send("continue")).text).toBe("primary recovered");
    expect(JSON.stringify(preferred.requests.at(-1)?.body.messages)).toContain("remember green");
    expect(JSON.stringify(preferred.requests.at(-1)?.body.messages)).toContain("reserve answered");
    expect(runtime.store.listMessages(runtime.store.primaryConversation().id).filter(m=>m.kind==="notice")).toEqual([]);
  } finally {
    vi.restoreAllMocks();await runtime.stop();await preferred.close();await reserve.close();vi.unstubAllEnvs();
    rmSync(root,{recursive:true,force:true,maxRetries:5});
  }
}, 60_000);
