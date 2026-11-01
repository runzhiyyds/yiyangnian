import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGateway } from '../src/gateway.js';

const env = { BUSINESS_GATEWAY_ENABLED: 'true' };
const gateway = createGateway();
const base = 'https://yiyangnian-api.pet-food-advisor.asia';

test('candidate is disabled unless explicitly enabled', async (t) => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('must not call'); });
  const response = await gateway.fetch(new Request(base + '/rest/v1/point_records'));
  assert.equal(response.status, 503);
});

test('login forwards its body and credentials once to the fixed project', async (t) => {
  let count = 0;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    count++;
    assert.equal(url.href, 'https://jhntjagskjklbrsgturh.supabase.co/auth/v1/token?grant_type=password');
    assert.equal(init.redirect, 'manual');
    assert.equal(init.headers.get('apikey'), 'public-fixture');
    assert.equal(init.headers.get('authorization'), 'Bearer user-fixture');
    assert.equal(init.headers.get('cookie'), null);
    assert.equal(init.headers.get('x-forwarded-host'), null);
    const body = await new Response(init.body).json();
    assert.deepEqual(body, { email: 'fixture@example.test', password: 'fixture-password' });
    return new Response('{"session":"fixture-session"}', { status: 200 });
  });
  const response = await gateway.fetch(new Request(base + '/auth/v1/token?grant_type=password', {
    method: 'POST', headers: { apikey: 'public-fixture', Authorization: 'Bearer user-fixture',
      Cookie: 'private-cookie', 'X-Forwarded-Host': 'attacker.test' },
    body: JSON.stringify({ email: 'fixture@example.test', password: 'fixture-password' }),
  }), env);
  assert.equal(await response.text(), '{"session":"fixture-session"}');
  assert.equal(count, 1);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
});

test('REST preserves query, pagination and authorization errors', async (t) => {
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    assert.equal(url.hostname, 'jhntjagskjklbrsgturh.supabase.co');
    assert.equal(url.searchParams.get('select'), 'id,total');
    assert.equal(init.headers.get('prefer'), 'count=exact');
    return new Response('{"message":"rls denied"}', { status: 403,
      headers: { 'Content-Range': '0-19/100', 'Set-Cookie': 'private-cookie' } });
  });
  const response = await gateway.fetch(new Request(base + '/rest/v1/point_records?select=id,total', {
    headers: { Prefer: 'count=exact' },
  }), env);
  assert.equal(response.status, 403);
  assert.equal(response.headers.get('Content-Range'), '0-19/100');
  assert.equal(response.headers.get('Set-Cookie'), null);
  assert.equal(await response.text(), '{"message":"rls denied"}');
});

test('RPC forwards the function name and arguments without replaying', async (t) => {
  let count = 0;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    count++;
    assert.equal(url.pathname, '/rest/v1/rpc/fixture_function');
    assert.equal(init.method, 'POST');
    assert.deepEqual(await new Response(init.body).json(), { fixture_arg: 3 });
    return new Response('[{"fixture_result":3}]');
  });
  const response = await gateway.fetch(new Request(base + '/rest/v1/rpc/fixture_function', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fixture_arg: 3 }),
  }), env);
  assert.deepEqual(await response.json(), [{ fixture_result: 3 }]);
  assert.equal(count, 1);
});

test('unsupported and encoded admin paths do not reach upstream', async (t) => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('must not call'); });
  for (const path of ['/admin', '/auth/v1/admin', '/auth/v1/%61dmin/users',
    '/auth/v1/%2561dmin/users', '/auth/v1//admin/users', '/functions/v1/unknown']) {
    const response = await gateway.fetch(new Request(base + path), env);
    assert.equal(response.status, 404, path);
  }
});

test('preflight carries no upstream request or cookies', async (t) => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('must not call'); });
  const response = await gateway.fetch(new Request(base + '/rest/v1/point_records', { method: 'OPTIONS' }), env);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
  assert.equal(response.headers.get('Access-Control-Allow-Credentials'), null);
});

test('upstream error never replays a write or reveals internal details', async (t) => {
  let count = 0;
  t.mock.method(globalThis, 'fetch', async () => { count++; throw new Error('private internals'); });
  const response = await gateway.fetch(new Request(base + '/rest/v1/point_records', {
    method: 'POST', body: '{}',
  }), env);
  assert.equal(response.status, 502);
  assert.equal(count, 1);
  assert.equal((await response.text()).includes('private'), false);
});

test('deadline aborts one request and rejects a late upstream response', async (t) => {
  let calls = 0;
  let aborted = false;
  let release;
  t.mock.method(globalThis, 'fetch', async (_url, init) => {
    calls++;
    init.signal.addEventListener('abort', () => { aborted = true; });
    return new Promise(resolve => { release = resolve; });
  });
  const response = await createGateway({ timeoutMs: 20 }).fetch(new Request(base + '/auth/v1/token', {
    method: 'POST', body: '{}',
  }), env);
  assert.equal(response.status, 504);
  assert.equal(aborted, true);
  assert.equal(calls, 1);
  let canceled = false;
  release(new Response(new ReadableStream({ cancel() { canceled = true; } })));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(canceled, true);
});

test('response body stall uses the same deadline', async (t) => {
  let canceled = false;
  t.mock.method(globalThis, 'fetch', async () => new Response(new ReadableStream({
    cancel() { canceled = true; },
  })));
  const response = await createGateway({ timeoutMs: 20 }).fetch(new Request(base + '/rest/v1/point_records'), env);
  await assert.rejects(response.text(), /timeout/);
  assert.equal(canceled, true);
});

test('same-project redirects use the gateway without following them', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => new Response(null, { status: 302,
    headers: { Location: 'https://jhntjagskjklbrsgturh.supabase.co/auth/v1/callback' } }));
  const response = await gateway.fetch(new Request(base + '/auth/v1/authorize'), env);
  assert.equal(response.headers.get('Location'), base + '/auth/v1/callback');
});

test('realtime upgrades pass through and cannot use arbitrary paths', async (t) => {
  const socketResponse = { status: 101, webSocket: {} };
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    assert.equal(url.pathname, '/realtime/v1/websocket');
    assert.equal(init.headers.get('Upgrade'), 'websocket');
    assert.equal(url.searchParams.get('apikey'), 'public-fixture');
    return socketResponse;
  });
  const response = await gateway.fetch(new Request(base + '/realtime/v1/websocket?apikey=public-fixture', {
    headers: { Upgrade: 'websocket' },
  }), env);
  assert.equal(response, socketResponse);
  const denied = await gateway.fetch(new Request(base + '/rest/v1/point_records', {
    headers: { Upgrade: 'websocket' },
  }), env);
  assert.equal(denied.status, 400);
});

test('storage bodies remain byte-identical', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => new Response(new Uint8Array([0, 255, 127]), {
    headers: { 'Content-Type': 'image/png' },
  }));
  const response = await gateway.fetch(new Request(base + '/storage/v1/object/public/fixture.png'), env);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), new Uint8Array([0, 255, 127]));
});
