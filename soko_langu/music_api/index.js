const express = require('express');
const axios = require('axios');

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '32kb' }));

const PORT = Number(process.env.PORT || 10000);
const JAMENDO_CLIENT_ID = process.env.JAMENDO_CLIENT_ID || '';
const IA_SEARCH = 'https://archive.org/advancedsearch.php';
const IA_META = 'https://archive.org/metadata';
const JAMENDO_API = 'https://api.jamendo.com/v3.0';

const http = axios.create({ timeout: 12000, headers: { 'User-Agent': 'SokoVibeMusic/1.0 (open-media catalog)' } });

function isOpenLicense(value) {
  const s = String(value || '').trim().toLowerCase().replace(/\\/g, '/');
  if (!s) return false;
  if (/by-nc|by-nd|sampling|developing|all rights reserved|copyright/.test(s)) return false;
  return s.includes('creativecommons.org/publicdomain/zero') ||
    s.includes('creativecommons.org/publicdomain/mark') ||
    /creativecommons.org/licenses/by(-sa)?\/(3\.0|4\.0)(\/|$)/.test(s) ||
}

function archiveItem(doc, kind) {
  const license = doc.licenseurl || doc.license || '';
  if (!isOpenLicense(license) || !doc.identifier) return null;
  return {
    id: doc.identifier,
    provider: 'internet-archive',
    kind,
    title: doc.title || 'Untitled',
    creator: doc.creator || doc.artist || 'Unknown creator',
    year: doc.year || null,
    image: 'https://archive.org/services/img/' + encodeURIComponent(doc.identifier),
    license,
    sourceUrl: 'https://archive.org/details/' + encodeURIComponent(doc.identifier),
    streamLookupUrl: '/api/v1/catalog/play/internet-archive/' + encodeURIComponent(doc.identifier) + '?kind=' + kind,
    downloadAllowed: true
  };
}

app.get('/health', (_req, res) => res.json({ ok: true, service: 'sokovibe-music-api', jamendoConfigured: Boolean(JAMENDO_CLIENT_ID) }));
app.get('/', (_req, res) => res.json({ service: 'SokoVibe Music API', status: 'ok', endpoints: ['/health', '/api/v1/catalog/search?q=ambient&kind=music', '/api/v1/catalog/search?q=animation&kind=movie'] }));

app.get('/api/v1/catalog/search', async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 120);
  const kind = req.query.kind === 'movie' ? 'movie' : 'music';
  const page = Math.max(1, Math.min(10, Number.parseInt(req.query.page, 10) || 1));
  if (!q) return res.status(400).json({ success: false, error: 'q is required' });

  const results = [];
  const warnings = [];
  try {
    // Escape Archive query syntax instead of accepting user-provided operators.
    const safe = q.replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim();
    const query = 'mediatype:' + (kind === 'movie' ? 'movies' : 'audio') +
      ' AND (title:(' + safe + ') OR creator:(' + safe + ') OR subject:(' + safe + '))';
    const response = await http.get(IA_SEARCH, { params: {
      q: query, fl: ['identifier','title','creator','artist','year','licenseurl','license','mediatype'],
      rows: 30, page, output: 'json', 'sort[]': 'downloads desc'
    }});
    for (const doc of (response.data && response.data.response && response.data.response.docs) || []) {
      const item = archiveItem(doc, kind);
      if (item) results.push(item);
    }
  } catch (_e) { warnings.push('internet-archive-unavailable'); }

  if (kind === 'music' && JAMENDO_CLIENT_ID) {
    try {
      const response = await http.get(JAMENDO_API + '/tracks/', { params: {
        client_id: JAMENDO_CLIENT_ID, format: 'json', limit: 25, namesearch: q,
        audioformat: 'mp32', include: 'licenses', order: 'popularity_total'
      }});
      for (const t of (response.data && response.data.results) || []) {
        const license = t.license_ccurl || '';
        if (!isOpenLicense(license) || !t.audio) continue;
        results.push({
          id: String(t.id), provider: 'jamendo', kind: 'music',
          title: t.name || 'Untitled', creator: t.artist_name || 'Unknown artist',
          album: t.album_name || null, image: t.album_image || null,
          duration: t.duration || null, license,
          sourceUrl: t.shareurl || 'https://www.jamendo.com/track/' + encodeURIComponent(t.id),
          streamUrl: t.audio, downloadAllowed: Boolean(t.audiodownload_allowed)
        });
      }
    } catch (_e) { warnings.push('jamendo-unavailable'); }
  }

  res.set('Cache-Control', 'public, max-age=60, stale-while-revalidate=120');
  return res.json({ success: true, kind, query: q, count: results.length, results,
    providers: kind === 'music' ? ['internet-archive', 'jamendo'] : ['internet-archive'],
    warnings, note: 'Only items with a recognized open license are returned. Verify the source license before redistribution.' });
});

app.get('/api/v1/catalog/play/internet-archive/:identifier', async (req, res) => {
  const id = String(req.params.identifier || '');
  if (!/^[a-zA-Z0-9._-]{1,180}$/.test(id)) return res.status(400).json({ success: false, error: 'Invalid item identifier' });
  const kind = req.query.kind === 'movie' ? 'movie' : 'music';
  try {
    const response = await http.get(IA_META + '/' + encodeURIComponent(id));
    const metadata = response.data || {};
    const license = metadata.metadata && (metadata.metadata.licenseurl || metadata.metadata.license) || '';
    if (!isOpenLicense(license)) return res.status(403).json({ success: false, error: 'This item does not have a recognized open license' });
    const files = (metadata.files || []).filter(f => {
      const name = String(f.name || '').toLowerCase();
      const format = String(f.format || '').toLowerCase();
      if (/(_thumb|\.xml$|\.torrent$|\.srt$|\.txt$|\.jpg$|\.jpeg$|\.png$|\.gif$|\.sqlite$)/.test(name)) return false;
      if (kind === 'movie') return /\.(mp4|webm|ogv|m4v)$/.test(name) || /mpeg4|webm|ogg video/.test(format);
      return /\.(mp3|ogg|oga|flac|wav|m4a|opus)$/.test(name) || /mp3|ogg|flac|wave|audio/.test(format);
    }).sort((a,b) => {
      const rank = f => {
        const n = String(f.name || '').toLowerCase();
        if (kind === 'movie') return n.endsWith('.mp4') ? 0 : n.endsWith('.webm') ? 1 : 2;
        return n.endsWith('.mp3') ? 0 : n.endsWith('.ogg') ? 1 : n.endsWith('.m4a') ? 2 : 3;
      };
      return rank(a) - rank(b) || Number(a.size || 0) - Number(b.size || 0);
    });
    const file = files[0];
    if (!file || !file.name) return res.status(404).json({ success: false, error: 'No compatible media file found' });
    const path = file.name.split('/').map(encodeURIComponent).join('/');
    const streamUrl = 'https://archive.org/download/' + encodeURIComponent(id) + '/' + path;
    return res.json({ success: true, provider: 'internet-archive', title: metadata.metadata && metadata.metadata.title || id,
      creator: metadata.metadata && metadata.metadata.creator || 'Unknown creator', license, streamUrl,
      sourceUrl: 'https://archive.org/details/' + encodeURIComponent(id),
      downloadAllowed: true, mediaType: kind, fileName: file.name });
  } catch (_e) { return res.status(502).json({ success: false, error: 'Could not retrieve media metadata' }); }
});

app.listen(PORT, '0.0.0.0', () => console.log('[SokoVibe Music API] listening on ' + PORT));
