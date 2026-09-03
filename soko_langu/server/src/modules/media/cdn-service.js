const config = require('../../config');

/**
 * Build a public CDN URL for a media key served from the R2 public bucket.
 * media.soko-vibe.co.tz/<bucket>/<key>
 */
function publicUrl({ kind, key }) {
  const base = config.r2.publicUrl.replace(/\/+$/, '');
  return `${base}/${kind === 'thumbnail' ? 'thumbnails' : kind === 'video' ? 'videos' : 'images'}/${key}`;
}

/**
 * Visitor/OG meta tags for shareable content.
 */
function ogTags({ title, description, imageUrl, type = 'website' }) {
  return [
    `<meta property="og:type" content="${type}">`,
    `<meta property="og:title" content="${title.replace(/"/g, '&quot;')}">`,
    description ? `<meta property="og:description" content="${description.replace(/"/g, '&quot;')}">` : '',
    imageUrl ? `<meta property="og:image" content="${imageUrl}">` : '',
  ].filter(Boolean).join('\n');
}

module.exports = { publicUrl, ogTags };
