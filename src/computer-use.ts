import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, isAbsolute } from 'node:path';
import { parse } from 'smol-toml';

/** Use the installed OpenAI provider. Never bundle its binaries or import the
 * owner's other plugins, credentials, or app permissions into an employee. */
export function findComputerUse(codexHome = resolve(homedir(),'.codex'), platform: string = process.platform): Record<string, any> | null {
  if (platform !== 'darwin') return null;
  try {
    const config = parse(readFileSync(resolve(codexHome,'config.toml'),'utf8')) as any;
    if (config.plugins?.['unified-computer-use@openai-bundled']?.enabled !== true) return null;
    const root = resolve(codexHome,'plugins/cache/openai-bundled/unified-computer-use');
    for (const version of readdirSync(root).sort((a,b)=>b.localeCompare(a,undefined,{numeric:true}))) {
      const source = JSON.parse(readFileSync(resolve(root,version,'.mcp.json'),'utf8')).mcpServers?.cua_repl;
      if (!source || source.enabled === false || typeof source.command !== 'string' || !isAbsolute(source.command) || !existsSync(source.command)
        || !Array.isArray(source.args) || typeof source.args[0] !== 'string' || !isAbsolute(source.args[0]) || !existsSync(source.args[0])) continue;
      return {command:source.command,args:source.args,env:{...source.env,SKY_CUA_SERVICE_NATIVE_PIPE_PATH:source.env?.SKY_CUA_SERVICE_NATIVE_PIPE_PATH ?? resolve(homedir(),"Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/IPC/computeruse.sock")},enabled:true,
        enabled_tools:['js','js_reset','turn_ended'],startup_timeout_sec:120,default_tools_approval_mode:'prompt'};
    }
  } catch { /* Missing or incomplete installation has an explicit setup path. */ }
  return null;
}

/** Read-only executable dependencies for Codex's sandboxed JS kernel. */
export function computerUseReadPaths(server: Record<string, any> | undefined): string[] {
  if (process.platform !== 'darwin' || !server?.enabled) return [];
  const command = server.command;
  if (typeof command !== 'string' || !isAbsolute(command)) return [];
  const resources = command.match(/^(.*\.app\/Contents\/Resources)\//)?.[1];
  const paths = ['/System/Library/OpenSSL', ...(resources ? [resolve(resources,'cua_node')] : [])];
  for (const name of ['SKY_CUA_SERVICE_PATH','CODEX_CLI_PATH']) {
    const path = server.env?.[name];
    if (typeof path === 'string' && isAbsolute(path)) paths.push(path);
  }
  return paths;
}
