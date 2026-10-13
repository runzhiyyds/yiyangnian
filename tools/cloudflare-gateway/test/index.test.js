import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';

test('unauthenticated HTTP response proves reachability without forwarding credentials', async (t) => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    calls++;
    assert.equal(url, 'https://jhntjagskjklbrsgturh.supabase.co/auth/v1/health');
    assert.equal(init.redirect, 'manual');
    assert.deepEqual(init.headers, { Accept: 'application/json' });
    assert.equal(init.body, undefined);
    return new Response('private upstream body', { status: 401 });
  });
  const response = await worker.fetch(new Request('https://probe.test/health?url=https://attacker.test', {
    headers: { Authorization: 'private-user-token', apikey: 'private-fixture' },
  }));
  assert.equal(calls, 1);
  const body = await response.json();
  assert.equal(body.upstreamReached, true);
  assert.equal(body.upstreamStatus, 401);
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(JSON.stringify(body).includes('private'), false);
});

test('POST cannot forward passwords', async (t) => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('must not call upstream'); });
  const response = await worker.fetch(new Request('https://probe.test/health', {
    method: 'POST', body: 'private-password',
  }));
  assert.equal(response.status, 405);
  assert.equal(response.headers.get('Allow'), 'GET');
});

test('other paths cannot act as an API proxy', async (t) => {
  t.mock.method(globalThis, 'fetch', () => { throw new Error('must not call upstream'); });
  const response = await worker.fetch(new Request('https://probe.test/auth/v1/token'));
  assert.equal(response.status, 404);
});

test('connection failure reports its layer without internal details', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => { throw new TypeError('private internal details'); });
  const response = await worker.fetch(new Request('https://probe.test/health'));
  assert.equal(response.status, 502);
  const body = await response.json();
  assert.equal(body.gatewayReached, true);
  assert.equal(body.upstreamReached, false);
  assert.equal(body.reason, 'upstream_connection_failed');
  assert.equal(JSON.stringify(body).includes('private'), false);
});

test('timeout stops with a distinct result', async (t) => {
  t.mock.method(globalThis, 'fetch', async () => { throw new DOMException('timeout', 'TimeoutError'); });
  const response = await worker.fetch(new Request('https://probe.test/health'));
  assert.equal(response.status, 504);
  assert.equal((await response.json()).reason, 'upstream_timeout');
});
