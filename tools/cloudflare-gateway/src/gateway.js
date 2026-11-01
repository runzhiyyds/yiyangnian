import health from './index.js';

const origin = 'https://jhntjagskjklbrsgturh.supabase.co';
const prefixes = ['/auth/v1/', '/rest/v1/', '/storage/v1/', '/realtime/v1/'];
const methods = ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'];
const allowedHeaders = ['authorization', 'apikey', 'content-type', 'accept', 'prefer',
  'x-client-info', 'range', 'x-upsert', 'if-none-match', 'if-modified-since',
  'x-supabase-api-version', 'x-request-id'];

function cors(headers = new Headers()) {
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', [...methods, 'OPTIONS'].join(', '));
  headers.set('Access-Control-Allow-Headers', allowedHeaders.join(', '));
  headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Range');
  headers.set('Cache-Control', 'no-store');
  return headers;
}

function error(status, message, code) {
  return new Response(JSON.stringify({ message, code }), {
    status, headers: cors(new Headers({ 'Content-Type': 'application/json' })),
  });
}

// Fixed-project business gateway. index.js remains available for rollback.
export function createGateway({ timeoutMs = 10000 } = {}) {
  return {
    async fetch(request, env = {}) {
      const url = new URL(request.url);
      if (url.pathname === '/health') return health.fetch(request);
      if (env.BUSINESS_GATEWAY_ENABLED !== 'true') {
        return error(503, '业务入口尚未启用。', 'gateway_disabled');
      }
      // Decode once for checking; never allow ambiguous traversal or admin APIs.
      let path;
      try { path = decodeURIComponent(url.pathname); } catch {
        return error(400, '请求路径无效。', 'invalid_path');
      }
      if (/[\\%]/.test(path) || path.includes('//')
          || path.split('/').some(p => p === '.' || p === '..')
          || !prefixes.some(prefix => path.startsWith(prefix))
          || path === '/auth/v1/admin' || path.startsWith('/auth/v1/admin/')) {
        return error(404, '请求路径不受支持。', 'unsupported_path');
      }
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors() });
      if (!methods.includes(request.method)) return error(405, '请求方法不受支持。', 'unsupported_method');
      // Client public keys and user JWTs retain Supabase's original authorization.
      // There is no service key, alternate upstream, request logging, or retry.
      const headers = new Headers();
      for (const key of allowedHeaders) {
        const value = request.headers.get(key);
        if (value !== null) headers.set(key, value);
      }
      const isSocket = request.headers.get('Upgrade')?.toLowerCase() === 'websocket';
      if (isSocket) {
        if (request.method !== 'GET' || path !== '/realtime/v1/websocket') {
          return error(400, '实时连接路径无效。', 'invalid_websocket');
        }
        headers.set('Upgrade', 'websocket');
      }
      const target = new URL(origin);
      target.pathname = url.pathname;
      target.search = url.search;
      const abort = new AbortController();
      let timedOut = false;
      let rejectDeadline;
      const deadline = new Promise((_, reject) => { rejectDeadline = reject; });
      const timer = setTimeout(() => {
        timedOut = true;
        abort.abort();
        rejectDeadline(new Error('Gateway timeout'));
      }, timeoutMs);
      const finish = () => clearTimeout(timer);
      try {
        const pending = fetch(target, {
          method: request.method, headers,
          body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
          signal: abort.signal, redirect: 'manual',
          cf: { cacheTtl: 0, cacheEverything: false },
          // Node's local test runner requires duplex for streamed request bodies.
          duplex: 'half',
        });
        pending.then(response => {
          if (timedOut) response.body?.cancel().catch(() => {});
        }, () => {});
        const response = await Promise.race([pending, deadline]);
        if (response.status === 101) {
          finish();
          return response;
        }
        const responseHeaders = cors(new Headers(response.headers));
        responseHeaders.delete('Set-Cookie');
        const location = responseHeaders.get('Location');
        if (location) {
          const redirect = new URL(location, target);
          if (redirect.origin === origin) {
            redirect.protocol = url.protocol;
            redirect.host = url.host;
            responseHeaders.set('Location', redirect.href);
          }
        }
        if (!response.body || request.method === 'HEAD') {
          finish();
          await response.body?.cancel();
          return new Response(null, { status: response.status, headers: responseHeaders });
        }
        const reader = response.body.getReader();
        let done = false;
        let onAbort;
        const cleanup = () => {
          done = true;
          finish();
          abort.signal.removeEventListener('abort', onAbort);
        };
        const body = new ReadableStream({
          start(controller) {
            onAbort = () => {
              if (done) return;
              cleanup();
              controller.error(new Error('Gateway response timeout'));
              reader.cancel().catch(() => {});
            };
            abort.signal.addEventListener('abort', onAbort);
            if (abort.signal.aborted) onAbort();
          },
          async pull(controller) {
            try {
              const part = await reader.read();
              if (done) return;
              if (part.done) { cleanup(); controller.close(); }
              else controller.enqueue(part.value);
            } catch (failure) {
              if (done) return;
              cleanup(); controller.error(failure);
            }
          },
          cancel(reason) {
            cleanup(); abort.abort();
            return reader.cancel(reason);
          },
        });
        return new Response(body, { status: response.status, headers: responseHeaders });
      } catch {
        finish();
        return timedOut
          ? error(504, '连接服务超时，请稍后重试。', 'gateway_timeout')
          : error(502, '暂时无法连接服务，请稍后重试。', 'gateway_connection_failed');
      }
    },
  };
}

export default createGateway();
