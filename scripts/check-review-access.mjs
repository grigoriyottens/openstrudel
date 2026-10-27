#!/usr/bin/env node
// A submission/deployment gate, not a periodic probe: requesting a fresh owner
// invitation replaces any unclaimed owner invitation. Paired devices stay valid.
import { readFile } from 'node:fs/promises';
import { connect } from 'node:tls';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

async function check() {
  const page = new URL((await readFile(process.argv[2], 'utf8')).trim());
  assert.equal(page.protocol, 'https:');
  const code = page.hash.slice(1);
  assert.match(code, /^[a-f0-9]{64}$/);
  page.hash = '';
  const get = async path => {
    const response = await fetch(new URL(path, page), { redirect: 'error', signal: AbortSignal.timeout(15000) });
    assert.equal(response.status, 200, path + ' must be available');
    assert.match(response.headers.get('cache-control') ?? '', /no-store/);
    return response;
  };
  const html = await (await get('')).text();
  assert.match(html, /setup\.js/);
  assert.ok(!html.includes(code), 'The page must not embed its secret');
  await get('setup.js');
  await get('localization.js');
  await get('localizations.json');
  assert.equal((await (await get('healthz')).json()).ok, true);
  const response = await fetch(new URL('pairing', page), {
    method: 'POST', headers: { authorization: 'Bearer ' + code, origin: page.origin },
    redirect: 'error', signal: AbortSignal.timeout(15000),
  });
  assert.equal(response.status, 201, 'The existing review code must issue a connection');
  const invitation = await response.json();
  assert.ok(Date.parse(invitation.expiresAt) > Date.now());
  const target = new URL(invitation.url);
  assert.equal(target.protocol, 'openstrudel:');
  assert.equal(target.hostname, 'connect');
  const host = target.searchParams.get('host');
  const port = Number(target.searchParams.get('port'));
  const pin = target.searchParams.get('keyPin');
  assert.equal(host, page.hostname);
  assert.ok(port > 0 && port <= 65535);
  assert.match(pin ?? '', /^[a-f0-9]{64}$/);
  await new Promise((resolve, reject) => {
    // The Home deliberately uses its own pinned identity, not the web certificate.
    const socket = connect({ host, port, rejectUnauthorized: false });
    socket.setTimeout(15000, () => socket.destroy(new Error('Home TLS timed out')));
    socket.once('error', reject);
    socket.once('secureConnect', () => {
      try {
        const cert = socket.getPeerX509Certificate();
        assert.ok(cert);
        assert.ok(Date.parse(cert.validFrom) <= Date.now() && Date.parse(cert.validTo) > Date.now());
        assert.equal(createHash('sha256').update(cert.publicKey.export({ type: 'spki', format: 'der' })).digest('hex'), pin);
        socket.end(); resolve();
      } catch (error) { socket.destroy(); reject(error); }
    });
  });
  console.log(JSON.stringify({ ok: true, page: page.href, pairing: true, homeTLS: true, checkedAt: new Date().toISOString() }));
}
check().catch(error => {
  // Never print the private URL, provider credentials, or a generated invitation.
  console.error('Review access check failed:', error.code ?? error.cause?.code ?? error.name);
  process.exitCode = 1;
});
