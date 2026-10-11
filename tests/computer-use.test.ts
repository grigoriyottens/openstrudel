import { expect, it, vi } from 'vitest';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { findComputerUse, computerUseReadPaths } from '../src/computer-use.js';
import * as computer from '../src/computer-use.js';
import { CodexExtensions, readToml } from '../src/extensions.js';
it('discovers only the installed official Computer Use provider; does not import unrelated tools or enable a disabled plugin',()=>{
 const root=mkdtempSync(join(tmpdir(),'strudel-computer-'));
 try {
  const dir=join(root,'plugins/cache/openai-bundled/unified-computer-use/1.0');mkdirSync(dir,{recursive:true});
  const command=join(root,'node'),script=join(root,'cua-repl.mjs');writeFileSync(command,'');writeFileSync(script,'');
  writeFileSync(join(dir,'.mcp.json'),JSON.stringify({mcpServers:{cua_repl:{command,args:[script],env:{CUA_REPL_ENABLED_SURFACES:'browser,computer'}},unrelated:{command:'never'}}}));
  expect(findComputerUse(root,'darwin')).toBeNull();
  writeFileSync(join(root,'config.toml'),'[plugins."unified-computer-use@openai-bundled"]\nenabled = true\n');
  expect(findComputerUse(root,'darwin')).toMatchObject({command,args:[script]});
  expect(findComputerUse(root,'linux')).toBeNull();
  rmSync(script);expect(findComputerUse(root,'darwin')).toBeNull();
 }finally{rmSync(root,{recursive:true,force:true});}
});

it('limits filesystem grants to provider dependencies and rolls back failed connection reloads',async()=>{
 const root=mkdtempSync(join(tmpdir(),'strudel-computer-scope-'));
 const server={enabled:true,command:'/Applications/ChatGPT.app/Contents/Resources/node',args:['/installed/cua.mjs'],env:{SKY_CUA_SERVICE_PATH:'/installed/kernel',CODEX_CLI_PATH:'/installed/codex'}};
 const installed=vi.spyOn(computer,'findComputerUse').mockReturnValue(server);
 try {
  writeFileSync(join(root,'config.toml'),'[permissions.openstrudel.filesystem]\n":minimal" = "read"\n"/work" = "write"\n');
  const before=readToml(join(root,'config.toml'));
  const changed=vi.fn(async()=>{});
  const manager=new CodexExtensions({home:root,cwd:root,sharedConfigPath:join(root,'shared/config.toml'),client:async()=>({}) as any,changed,idle:()=>true});
  changed.mockRejectedValueOnce(new Error('reload failed'));
  await expect(manager.connectComputerUse()).rejects.toThrow('reload failed');
  expect(readToml(join(root,'config.toml'))).toEqual(before);
  await manager.connectComputerUse();
  const config=readToml(join(root,'config.toml'));
  expect(config.mcp_servers.cua_repl).toEqual(server);
  expect(Object.keys(config.permissions.openstrudel.filesystem)).toEqual([':minimal','/work',...computerUseReadPaths(server)]);
  expect(readToml(join(root,'shared/config.toml')).permissions).toBeUndefined();
  await manager.removeMcp('cua_repl');
  expect(readToml(join(root,'config.toml')).permissions).toEqual(before.permissions);
 }finally{installed.mockRestore();rmSync(root,{recursive:true,force:true});}
});
