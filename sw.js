// Install Board service worker: shows team alerts. It does not cache the app, so updates always load fresh.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: 'Install Board', body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Install Board', {
    body: d.body || '',
    tag: d.tag || undefined,
    icon: 'icon.png',
    badge: 'icon.png',
    data: { url: d.url || './' }
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const target = new URL((e.notification.data && e.notification.data.url) || './', self.registration.scope);
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const w of wins) {
      if (new URL(w.url).origin === target.origin) {
        await w.focus();
        w.postMessage({ type: 'open', hash: target.hash });
        return;
      }
    }
    await self.clients.openWindow(target.href);
  })());
});
