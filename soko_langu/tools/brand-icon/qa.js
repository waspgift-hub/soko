// Visual QA sheet: renders every fitted variant at its true on-device pixel size
// (then magnified with nearest-neighbour) next to the source artwork, so the
// trace can be eyeballed before anything is written into the app.
//
//   node qa.js          overview of every fit
//   node qa.js sizes    legibility sweep for the notification / favicon sizes
const path = require('path');
const sharp = require('sharp');
const { master, svgMark, svgTile } = require('./svg.js');

const CAPTION = 18;
const CELL = 250;
const HERE = __dirname;

// Builds one cell. `frac` overrides the named fit so a size can be tried
// without editing trace.js and re-running potrace.
async function cell({ fit, frac, color, px, bg, caption, magnify = 4 }) {
  const svg = frac ? svgMark(frac, color, px) : svgMark(fit, color, px);
  const art = await sharp(Buffer.from(svg))
    .resize(px * magnify, px * magnify, { kernel: 'nearest' })
    .png()
    .toBuffer();

  const inner = Math.min(CELL - 16, px * magnify);
  const captionFill = bg === '#ffffff' ? '#000000' : '#ffffff';
  return sharp(
    Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${CELL}" height="${CELL + CAPTION}">` +
        `<rect x="0" y="0" width="${CELL}" height="${CELL + CAPTION}" fill="${bg}"/>` +
        `<image href="data:image/png;base64,${art.toString('base64')}" ` +
        `x="${(CELL - inner) / 2}" y="${(CELL - inner) / 2}" width="${inner}" height="${inner}" ` +
        `image-rendering="pixelated"/>` +
        `<rect x="0" y="${CELL}" width="${CELL}" height="${CAPTION}" fill="#000000"/>` +
        `<text x="${CELL / 2}" y="${CELL + 13}" font-family="monospace" font-size="11" ` +
        `text-anchor="middle" fill="${captionFill}">${caption}</text>` +
        `</svg>`,
    ),
  )
    .png()
    .toBuffer();
}

async function sourceCell() {
  const art = await sharp(master.source).resize(CELL - 16, CELL - 16).png().toBuffer();
  return sharp(
    Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${CELL}" height="${CELL + CAPTION}">` +
        `<rect x="0" y="0" width="${CELL}" height="${CELL + CAPTION}" fill="#f0f0f0"/>` +
        `<image href="data:image/png;base64,${art.toString('base64')}" x="8" y="8" width="${CELL - 16}" height="${CELL - 16}"/>` +
        `<rect x="0" y="${CELL}" width="${CELL}" height="${CAPTION}" fill="#000000"/>` +
        `<text x="${CELL / 2}" y="${CELL + 13}" font-family="monospace" font-size="11" text-anchor="middle" fill="#ffffff">source 1920</text>` +
        `</svg>`,
    ),
  )
    .png()
    .toBuffer();
}

const OVERVIEW = async () => [
  [
    await sourceCell(),
    await cell({ fit: 'icon', color: '#000000', px: 256, bg: '#ffffff', caption: 'icon (launcher)', magnify: 1 }),
    await cell({ fit: 'maskable', color: '#000000', px: 256, bg: '#ffffff', caption: 'maskable', magnify: 1 }),
    await cell({ fit: 'adaptiveFg', color: '#000000', px: 256, bg: '#ffffff', caption: 'adaptiveFg', magnify: 1 }),
  ],
  [
    await cell({ fit: 'notification', color: '#ffffff', px: 24, bg: '#1b1b1b', caption: 'notif 24dp (x10)', magnify: 10 }),
    await cell({ fit: 'notification', color: '#ffffff', px: 48, bg: '#1b1b1b', caption: 'notif 48px (x5)', magnify: 5 }),
    await cell({ fit: 'faviconSmall', color: '#000000', px: 16, bg: '#ffffff', caption: 'favicon 16 (x15)', magnify: 15 }),
    await cell({ fit: 'appleTouch', color: '#000000', px: 180, bg: '#ffffff', caption: 'apple-touch 180', magnify: 1 }),
  ],
];

const SIZES = async () => [
  [
    await cell({ frac: 0.94, color: '#ffffff', px: 24, bg: '#1b1b1b', caption: 'notif 24dp frac=0.94', magnify: 10 }),
    await cell({ frac: 0.86, color: '#ffffff', px: 24, bg: '#1b1b1b', caption: 'notif 24dp frac=0.86', magnify: 10 }),
    await cell({ frac: 0.8, color: '#ffffff', px: 24, bg: '#1b1b1b', caption: 'notif 24dp frac=0.80', magnify: 10 }),
    await cell({ frac: 0.72, color: '#ffffff', px: 24, bg: '#1b1b1b', caption: 'notif 24dp frac=0.72', magnify: 10 }),
  ],
  [
    await cell({ frac: 0.78, color: '#000000', px: 16, bg: '#ffffff', caption: 'favicon 16 frac=0.78', magnify: 15 }),
    await cell({ frac: 0.72, color: '#000000', px: 16, bg: '#ffffff', caption: 'favicon 16 frac=0.72', magnify: 15 }),
    await cell({ frac: 0.66, color: '#000000', px: 16, bg: '#ffffff', caption: 'favicon 16 frac=0.66', magnify: 15 }),
    await cell({ fit: 'favicon', color: '#000000', px: 32, bg: '#ffffff', caption: 'favicon 32', magnify: 7 }),
  ],
];

(async () => {
  const rows = process.argv[2] === 'sizes' ? await SIZES() : await OVERVIEW();
  const strips = [];
  for (const r of rows) {
    strips.push(
      await sharp({ create: { width: r.length * CELL, height: CELL + CAPTION, channels: 4, background: '#000000' } })
        .composite(r.map((buf, i) => ({ input: buf, top: 0, left: i * CELL })))
        .png()
        .toBuffer(),
    );
  }
  await sharp({
    create: { width: 4 * CELL, height: strips.length * (CELL + CAPTION), channels: 4, background: '#000000' },
  })
    .composite(strips.map((s, i) => ({ input: s, top: i * (CELL + CAPTION), left: 0 })))
    .png()
    .toFile(path.join(HERE, 'qa.png'));
  console.log('wrote qa.png');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});