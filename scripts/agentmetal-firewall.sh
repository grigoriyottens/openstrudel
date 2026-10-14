#!/bin/bash
# Runs only over the new server's pinned SSH connection. No provider account
# credentials are needed: AgentMetal authenticates its own VM by source IP.
prepare_agentmetal() {
  python3 - "$@" <<'OPENSTRUDEL_AGENTMETAL'
import datetime, json, sys, urllib.request

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('redirect')

def request(path, body=None):
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request('https://api.agentmetal.dev' + path, data=payload,
                                 headers={'Accept': 'application/json', 'Content-Type': 'application/json'})
    with urllib.request.build_opener(NoRedirect).open(req, timeout=8) as response:
        data = response.read(262145)
        if len(data) > 262144:
            raise ValueError('response')
        return json.loads(data)

def has_port(firewall):
    return firewall.get('managed') is True and any(
        rule.get('protocol') == 'tcp' and str(rule.get('port')) == '7789'
        and '0.0.0.0/0' in rule.get('source_ips', ['0.0.0.0/0'])
        for rule in firewall.get('rules', []))

try:
    server_id, address = sys.argv[1:]
    identity = request('/v1/self')
    if identity.get('server_id') != server_id or identity.get('ipv4') != address:
        print(json.dumps({'ok': False, 'problem': 'identity'}))
    elif datetime.datetime.fromisoformat(identity['expires_at'].replace('Z', '+00:00')) <= datetime.datetime.now(datetime.timezone.utc):
        print(json.dumps({'ok': False, 'problem': 'expired'}))
    else:
        path = '/v1/servers/' + server_id + '/firewall'
        firewall = request(path)
        if firewall.get('managed') is not True:
            raise ValueError('unmanaged firewall')
        if not has_port(firewall):
            request(path + '/rules', {'protocol': 'tcp', 'port': '7789'})
            firewall = request(path)
        print(json.dumps({'ok': has_port(firewall), 'expiresAt': identity['expires_at']}))
except Exception:
    # Provider responses and diagnostics must never leak credentials to logs.
    print(json.dumps({'ok': False, 'problem': 'firewall'}))
OPENSTRUDEL_AGENTMETAL
}
