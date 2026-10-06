const RELEASES_API = 'https://api.github.com/repos/susu177990-rgb/otato-prompt/releases';

// Follow every release page; count installer assets rather than release metadata.
export async function getDownloads(fetchRelease = fetch) {
  let total = 0;
  for (let page = 1; ; page++) {
    const response = await fetchRelease(`${RELEASES_API}?per_page=100&page=${page}`, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'otato-prompt-website' },
      signal: AbortSignal.timeout(10000)
    });
    if (!response.ok) throw new Error(`Release statistics returned ${response.status}`);
    const releases = await response.json();
    if (!Array.isArray(releases)) throw new Error('Invalid release statistics');
    for (const release of releases) {
      if (release.draft) continue;
      for (const asset of release.assets ?? []) {
        if (!/^oTATo-prompt\.(dmg|zip)$/i.test(asset.name)) continue;
        if (!Number.isSafeInteger(asset.download_count) || asset.download_count < 0) {
          throw new Error('Invalid download count');
        }
        total += asset.download_count;
      }
    }
    if (!(response.headers.get('Link') ?? '').includes('rel="next"')) break;
  }
  return { total, updatedAt: new Date().toISOString() };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== '/api/downloads') return env.ASSETS.fetch(request);
    if (request.method !== 'GET') {
      return new Response(null, { status: 405, headers: { Allow: 'GET' } });
    }
    const key = new Request(`${url.origin}/api/downloads`);
    const cache = caches.default;
    const cached = await cache.match(key);
    const previous = cached ? await cached.json() : null;
    if (previous && Date.now() - Date.parse(previous.updatedAt) < 900000) {
      return Response.json(previous, { headers: { 'Cache-Control': 'public, max-age=300' } });
    }
    try {
      const data = await getDownloads();
      const response = Response.json(data, {
        headers: {
          'Cache-Control': 'public, max-age=300',
          'X-Content-Type-Options': 'nosniff'
        }
      });
      // Keep the last valid value for a day, but refresh it after 15 minutes.
      const saved = response.clone();
      saved.headers.set('Cache-Control', 'public, max-age=86400');
      ctx.waitUntil(cache.put(key, saved).catch(() => {}));
      return response;
    } catch (error) {
      console.warn('Download statistics unavailable:', error.message);
      if (previous) {
        return Response.json({ ...previous, stale: true }, {
          headers: { 'Cache-Control': 'public, max-age=60' }
        });
      }
      return Response.json({ error: 'Statistics temporarily unavailable' }, {
        status: 503, headers: { 'Cache-Control': 'no-store' }
      });
    }
  }
};
