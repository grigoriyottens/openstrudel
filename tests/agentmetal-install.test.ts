import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';

// Execute the actual remote script with an in-process HTTP fixture. No server
// is purchased and no real provider firewall is touched by these tests.
const script = readFileSync('scripts/agentmetal-firewall.sh', 'utf8').split("<<'OPENSTRUDEL_AGENTMETAL'\n")[1].split('\nOPENSTRUDEL_AGENTMETAL')[0];
function prepare(options: { wrongID?: boolean; expired?: boolean; opened?: boolean; invalidAfterWrite?: boolean } = {}) {
  const fixture = `
import json, urllib.request, sys
options = json.loads(${JSON.stringify(JSON.stringify(options))})
calls = []
opened = options.get('opened', False)
class Response:
    def __init__(self, data): self.data = data
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self, limit): return json.dumps(self.data).encode()
class Opener:
    def open(self, req, timeout):
        global opened
        calls.append({'url':req.full_url, 'method':req.get_method(), 'body':json.loads(req.data) if req.data else None})
        if req.full_url.endswith('/self'):
            return Response({'server_id':'srv_other' if options.get('wrongID') else 'srv_fixture','ipv4':'8.8.4.4','expires_at':'2020-01-01T00:00:00Z' if options.get('expired') else '2099-01-01T00:00:00.123Z'})
        if req.get_method() == 'POST':
            opened = not options.get('invalidAfterWrite', False)
            return Response({'ok':True})
        return Response({'managed':True,'rules':[{'protocol':'tcp','port':'22'}] + ([{'protocol':'tcp','port':'7789','source_ips':['0.0.0.0/0']}] if opened else [])})
urllib.request.build_opener = lambda *args: Opener()
`;
  const output = execFileSync('python3', ['-c', fixture + script + '\nprint(json.dumps(calls))', 'srv_fixture', '8.8.4.4'], {encoding:'utf8', timeout:10000}).trim().split('\n');
  return {result:JSON.parse(output[0]), calls:JSON.parse(output[1]) as Array<{url:string; method:string; body:unknown}>};
}
describe('AgentMetal instance setup', () => {
  it('opens only the required port, then verifies it at the network edge', () => {
    const { result, calls } = prepare();
    expect(result.ok).toBe(true);
    expect(calls.filter(c => c.method === 'POST')).toEqual([{url:'https://api.agentmetal.dev/v1/servers/srv_fixture/firewall/rules', method:'POST', body:{protocol:'tcp',port:'7789'}}]);
    expect(calls.at(-1)?.method).toBe('GET');
  });
  it('does not duplicate the rule on a retry', () => {
    const {result,calls} = prepare({opened:true});
    expect(result.ok).toBe(true);
    expect(calls.every(c => c.method === 'GET')).toBe(true);
  });
  it.each([{wrongID:true}, {expired:true}])('never changes another or expired instance: %j', options => {
    const {result,calls} = prepare(options);
    expect(result.ok).toBe(false);
    expect(calls).toHaveLength(1);
  });
  it('does not treat a successful write response as proof the port is open', () => {
    expect(prepare({invalidAfterWrite:true}).result.ok).toBe(false);
  });
});
