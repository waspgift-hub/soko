// Soko Vibe app-shell service worker
// Caches only static Flutter shell/runtime assets.
// Product data, Firebase/HTTP API responses, auth state, orders and transactions
// are intentionally NOT cached.

const CACHE_NAME = 'soko-vibe-shell-v1';

const SHELL = [
  './',
  './index.html',
  './flutter_bootstrap.js',
  './flutter.js',
  './main.dart.js',
  './manifest.json',
  './favicon.ico',
  './favicon.png',
  './favicon-16x16.png',
  './favicon-32x32.png',
  './apple-touch-icon.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      // A missing optional/generated file must not prevent the whole shell
      // from being installed.
      await Promise.all(
        SHELL.map((url) =>
          fetch(url, { cache: 'no-cache' })
            .then((response) => {
              if (response.ok) return cache.put(url, response);
            })
            .catch(() => undefined)
        )
      );
      await self.skipWaiting();
    })
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Never intercept/cache cross-origin requests. This keeps Firebase,
  // api.sokovibe.co.tz, payment services, analytics, etc. network-only.
  if (url.origin !== self.location.origin) return;

  const path = url.pathname;

  const isShellFile =
    path.endsWith('/index.html') ||
    path.endsWith('/flutter_bootstrap.js') ||
    path.endsWith('/flutter.js') ||
    path.endsWith('/main.dart.js') ||
    path.endsWith('/manifest.json') ||
    path.endsWith('/favicon.ico') ||
    path.endsWith('/favicon.png') ||
    path.endsWith('/favicon-16x16.png') ||
    path.endsWith('/favicon-32x32.png') ||
    path.endsWith('/apple-touch-icon.png') ||
    path.endsWith('/assets/AssetManifest.json') ||
    path.endsWith('/assets/AssetManifest.bin.json') ||
    path.endsWith('/assets/FontManifest.json') ||
    path.includes('/canvaskit/');

  if (!isShellFile) return;

  event.respondWith(
    caches.match(request).then((cached) => {
      if (cached) return cached;

      return fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
        }
        return response;
      });
    })
  );
});
