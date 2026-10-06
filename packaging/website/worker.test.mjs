import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { getDownloads } from './worker.mjs';

const asset = (name, download_count) => ({ name, download_count });

test('all release pages contribute installer downloads, not metadata or drafts', async () => {
  const urls = [];
  const data = await getDownloads(async url => {
    urls.push(url);
    return urls.length === 1
      ? Response.json([
        { assets: [asset('oTATo-prompt.dmg', 5), asset('oTATo-prompt.zip', 3), asset('appcast.xml', 99)] },
        { draft: true, assets: [asset('oTATo-prompt.zip', 100)] }
      ], { headers: { Link: '<unused>; rel="next"' } })
      : Response.json([{ assets: [asset('oTATo-prompt.zip', 7), asset('release.json', 100)] }]);
  });
  assert.equal(data.total, 15);
  assert.equal(urls.length, 2);
  assert.match(urls[1], /page=2$/);
});

test('a later page failure cannot return a misleading partial count', async () => {
  let page = 0;
  await assert.rejects(getDownloads(async () => ++page === 1
    ? Response.json([{ assets: [asset('oTATo-prompt.dmg', 9)] }], { headers: { Link: '<unused>; rel="next"' } })
    : new Response('', { status: 403 })));
  await assert.rejects(getDownloads(async () => Response.json([{ assets: [asset('oTATo-prompt.zip', -1)] }])));
  assert.equal((await getDownloads(async () => Response.json([]))).total, 0);
});

test('static routing, fresh cache and stale cache fallback', async () => {
  const request = new Request('https://example.com/api/downloads');
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  const waits = [];
  const ctx = { waitUntil: promise => waits.push(promise) };
  try {
    const staticResponse = await worker.fetch(new Request('https://example.com/help.html'), {
      ASSETS: { fetch: async () => new Response('help page') }
    }, ctx);
    assert.equal(await staticResponse.text(), 'help page');
    assert.equal((await worker.fetch(new Request(request.url, { method: 'POST' }), {}, ctx)).status, 405);
    const now = new Date().toISOString();
    globalThis.caches = { default: { match: async () => Response.json({ total: 15, updatedAt: now }) } };
    globalThis.fetch = async () => { throw new Error('Network unavailable'); };
    assert.equal((await (await worker.fetch(request, {}, ctx)).json()).total, 15);
    globalThis.caches.default.match = async () => Response.json({ total: 15, updatedAt: '2020-01-01T00:00:00Z' });
    const fallback = await (await worker.fetch(request, {}, ctx)).json();
    assert.equal(fallback.total, 15);
    assert.equal(fallback.stale, true);
    globalThis.caches.default.match = async () => undefined;
    assert.equal((await worker.fetch(request, {}, ctx)).status, 503);
    let saved;
    globalThis.caches.default.put = async (_, response) => { saved = response; };
    globalThis.fetch = async () => Response.json([{ assets: [asset('oTATo-prompt.zip', 20)] }]);
    const response = await worker.fetch(request, {}, ctx);
    assert.equal((await response.json()).total, 20);
    await Promise.all(waits);
    assert.equal(saved.headers.get('Cache-Control'), 'public, max-age=86400');
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.caches = originalCaches;
  }
});
