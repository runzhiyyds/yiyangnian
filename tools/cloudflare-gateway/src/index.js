// Diagnostic only: no login, API keys, arbitrary upstreams, or data forwarding.
const upstream = 'https://jhntjagskjklbrsgturh.supabase.co/auth/v1/health';

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  });
}

export default {
  async fetch(request) {
    if (new URL(request.url).pathname !== '/health') {
      return json({ message: 'Use GET /health' }, 404);
    }
    if (request.method !== 'GET') {
      return json({ message: 'Only GET is supported' }, 405, { Allow: 'GET' });
    }
    const started = Date.now();
    try {
      const response = await fetch(upstream, {
        method: 'GET',
        redirect: 'manual',
        signal: AbortSignal.timeout(8000),
        headers: { Accept: 'application/json' },
      });
      // An unauthenticated 401 is expected. It proves HTTP reachability,
      // not password-login success or database health.
      const status = response.status;
      await response.body?.cancel();
      return json({ gatewayReached: true, upstreamReached: true,
        upstreamStatus: status, elapsedMs: Date.now() - started });
    } catch (error) {
      const timedOut = error.name === 'TimeoutError' || error.name === 'AbortError';
      return json({ gatewayReached: true, upstreamReached: false,
        reason: timedOut ? 'upstream_timeout' : 'upstream_connection_failed',
        elapsedMs: Date.now() - started }, timedOut ? 504 : 502);
    }
  },
};
