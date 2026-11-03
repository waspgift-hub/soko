const { Router } = require('express');
const axios = require('axios');

const router = Router();
const IA_SEARCH = 'https://archive.org/advancedsearch.php';
const IA_META = 'https://archive.org/metadata';
const JAMENDO_API = 'https://api.jamendo.com/v3.0';

const ALLOWED_LICENSES = [
  'creativecommons.org/publicdomain/zero',
  'creativecommons.org/licenses/by/',
  'creativecommons.org/licenses/by-sa/',
  'creativecommons.org/licenses/by/4.0',
  'creativecommons.org/licenses/by-sa/4.0',
  'creativecommons.org/licenses/by/3.0',
  'creativecommons.org/licenses/by-sa/3.0',
  'creativecommons.org/publicdomain/mark',
  'creativecommons.org/licenses/publicdomain',
];

function allowedLicense(value = '') {
  const license = String(value).toLowerCase();
  if (!license) return false;
  if (license.includes('/by-nc') || license.includes('/by-nd') ||
      license.includes('/sampling') || license.includes('/developing')) return false;
  return ALLOWED_LICENSES.some((part) => license.includes(part));
}

function normalizeArchiveDoc(doc, kind) {
  const license = doc.licenseurl || doc.license || '';
  if (!allowedLicense(license)) return null;
  return {
    id: doc.identifier,
    provider: 'internet-archive',
    kind,
    title: doc.title || 'Untitled',
    creator: doc.creator || doc.artist || 'Unknown creator',
    year: doc.year || null,
    license,
    sourceUrl: `https://archive.org/details/${encodeURIComponent(doc.identifier)}`,
    playbackEndpoint: `/api/v1/catalog/play/internet-archive/${encodeURIComponent(doc.identifier)}?kind=${kind}`,
    downloadAllowed: true,
  };
}

router.get('/search', async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 160);
  const kind = req.query.kind === 'movie' ? 'movie' : 'music';
  const page = Math.max(1, Math.min(20, Number.parseInt(req.query.page, 10) || 1));
  if (!q) return res.status(400).json({ success: false, error: 'q is required' });

  const results = [];
  const errors = [];
  try {
    const query = `(${kind === 'movie' ? 'mediatype:movies' : 'mediatype:audio'}) AND (title:(${q}) OR creator:(${q}) OR subject:(${q}))`;
    const response = await axios.get(IA_SEARCH, {
      params: {
        q: query,
        fl: ['identifier', 'title', 'creator', 'year', 'licenseurl', 'mediatype'],
        rows: 30,
        page,
        output: 'json',
        'sort[]': 'downloads desc',
      },
      timeout: 10000,
    });
    for (const doc of response.data?.response?.docs || []) {
      const item = normalizeArchiveDoc(doc, kind);
      if (item) results.push(item);
    }
  } catch (e) {
    errors.push('internet-archive-unavailable');
  }

  if (kind === 'music' && process.env.JAMENDO_CLIENT_ID) {
    try {
      const response = await axios.get(`${JAMENDO_API}/tracks/`, {
        params: {
          client_id: process.env.JAMENDO_CLIENT_ID,
          format: 'json',
          limit: 20,
          namesearch: q,
          audioformat: 'mp32',
          include: 'licenses',
          order: 'popularity_total',
        },
        timeout: 10000,
      });
      for (const track of response.data?.results || []) {
        const license = track.license_ccurl || '';
        if (!allowedLicense(license) || !track.audio) continue;
        results.push({
          id: String(track.id),
          provider: 'jamendo',
          kind: 'music',
          title: track.name || 'Untitled',
          creator: track.artist_name || 'Unknown artist',
          album: track.album_name || null,
          image: track.album_image || null,
          duration: track.duration || null,
          license,
          sourceUrl: track.shareurl || `https://www.jamendo.com/track/${track.id}`,
          streamUrl: track.audio,
          downloadAllowed: Boolean(track.audiodownload_allowed),
        });
      }
    } catch (e) {
      errors.push('jamendo-unavailable');
    }
  }

  res.set('Cache-Control', 'public, max-age=60, stale-while-revalidate=120');
  return res.json({
    success: true,
    kind,
    query: q,
    count: results.length,
    results,
    providers: kind === 'music' ? ['internet-archive', 'jamendo'] : ['internet-archive'],
    warnings: errors,
  });
});

router.get('/play/internet-archive/:identifier', async (req, res) => {
  const identifier = String(req.params.identifier || '');
  if (!/^[a-zA-Z0-9._-]{1,180}$/.test(identifier)) {
    return res.status(400).json({ success: false, error: 'Invalid item identifier' });
  }
  const kind = req.query.kind === 'movie' ? 'movie' : 'music';
  try {
    const response = await axios.get(`${IA_META}/${encodeURIComponent(identifier)}`, { timeout: 10000 });
    const metadata = response.data || {};
    const license = metadata.metadata?.licenseurl || metadata.metadata?.license || '';
    if (!allowedLicense(license)) {
      return res.status(403).json({ success: false, error: 'This item does not have a supported open license' });
    }
    const files = (metadata.files || []).filter((f) => {
      const name = String(f.name || '').toLowerCase();
      const format = String(f.format || '').toLowerCase();
      if (name.includes('_thumb') || name.endsWith('.xml') || name.endsWith('.torrent') ||
          name.endsWith('.srt') || name.endsWith('.txt') || name.endsWith('.jpg') ||
          name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif')) return false;
      if (kind === 'movie') return /\.(mp4|webm|ogv|m4v)$/.test(name) || /mpeg4|webm|ogg video/.test(format);
      return /\.(mp3|ogg|oga|flac|wav|m4a|opus)$/.test(name) || /mp3|ogg|flac|wave|audio/.test(format);
    }).sort((a, b) => Number(b.size || 0) - Number(a.size || 0));
    const file = files[0];
    if (!file?.name) return res.status(404).json({ success: false, error: 'No compatible media file found' });
    const encodedPath = file.name.split('/').map(encodeURIComponent).join('/');
    return res.json({
      success: true,
      provider: 'internet-archive',
      title: metadata.metadata?.title || identifier,
      creator: metadata.metadata?.creator || 'Unknown creator',
      license,
      streamUrl: `https://archive.org/download/${encodeURIComponent(identifier)}/${encodedPath}`,
      sourceUrl: `https://archive.org/details/${encodeURIComponent(identifier)}`,
      downloadAllowed: true,
      mediaType: kind,
    });
  } catch (e) {
    return res.status(502).json({ success: false, error: 'Could not retrieve media metadata' });
  }
});

module.exports = router;
