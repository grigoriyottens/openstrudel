/** Isolated example content for public screenshots. Never loads personal data. */
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { OpenStrudelRuntime } from "../../src/runtime.js";
import { MockCodexEngine } from "../../src/codex.js";
import { createServer } from "node:http";

const output = resolve(process.argv[2]!);
const directory = await mkdtemp(join(tmpdir(), "strudel-store-preview-"));
process.chdir(directory);
process.env.OPENSTRUDEL_PORT = "0";
const runtime = new OpenStrudelRuntime({dbPath: ":memory:", engine: new MockCodexEngine(), rootDirectory: directory, startTelegram: false});
const signedIn = !process.argv.includes("--sign-in");
runtime.account.read = async () => ({ connected: signedIn, email: signedIn ? "you@example.com" : null, managed: true, planType: signedIn ? "plus" : null });
let loginStarts = 0;
if (!signedIn) {
  runtime.account.startLogin = async () => {
    loginStarts++;
    await new Promise(done => setTimeout(done, 1500));
    return {type: "device", loginId: "onboarding-test", verificationUrl: `http://127.0.0.1:${(control.address() as {port:number}).port}/auth`, userCode: "TEST-12345"};
  };
  runtime.account.status = async () => ({loginId: "onboarding-test", status: "pending"});
  runtime.account.cancel = async () => ({loginId: "onboarding-test", status: "canceled"});
}
// Disposable fixture only: use ephemeral ports and loopback, not production defaults.
Object.assign((runtime.api.mobile as any).options, { port: 0, host: "127.0.0.1", hostname: "127.0.0.1" });
const editor = runtime.store.createProfile({ name: "Editor", instructions: "Write clearly and preserve my voice. Suggest one strong version and explain the main edit.", domain: "work" });
runtime.store.createProfile({ name: "Researcher", instructions: "Find original sources, compare options and explain what you have checked.", domain: "work" });
runtime.store.createProfile({ name: "Personal assistant", instructions: "Help me plan my day and keep important things close at hand. Ask only what you need to know.", domain: "personal" });
const conversation = runtime.store.profileConversation(editor.id);
runtime.store.importHistory(conversation.id, [
  {sourceId:"one",author:"You",date:"2026-10-12T06:40:00Z",direction:"inbound",text:"Help me announce our new workshop. Keep it short and warm, without sounding like an ad."},
  {sourceId:"two",author:"Editor",date:"2026-10-12T06:41:00Z",direction:"outbound",text:"## A place for your ideas\n\nOur workshop opens on Saturday. Bring the idea you've been meaning to try. We'll help you make a start.\n\n**17 October · noon to 6 pm**\n\nThe coffee and tools are ready. All that's missing is you.\n\n> I kept the details people need: what it is, when to come and what to bring."},
]);
const primary=runtime.store.primaryConversation();
runtime.store.importHistory(primary.id,[{sourceId:"intro",author:"OpenStrudel",date:"2026-10-12T06:39:00Z",direction:"outbound",text:"What would you like to do today?"}]);
await runtime.start();
const control=createServer(async(req,res)=>{
  res.setHeader("content-type","application/json");
  if(req.url==="/invite") {const invitation=await runtime.api.mobile.invite(true);const url=new URL(invitation.url);url.searchParams.set("name","My Mac");res.end(JSON.stringify({...invitation,url:url.toString()}));return;}
  res.end(JSON.stringify({editor:editor.id, loginStarts}));
});
await new Promise<void>(done=>control.listen(0,"127.0.0.1",done));
await writeFile(output,JSON.stringify({url:`http://127.0.0.1:${(control.address() as {port:number}).port}`,editor:editor.id}),{mode:0o600});
console.log("Private screenshot fixture ready; example content only.");
const stop=async()=>{control.close();await runtime.stop();await rm(directory,{recursive:true,force:true});process.exit(0);};
process.once("SIGTERM",stop);process.once("SIGINT",stop);
