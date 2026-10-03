// Mask simulation: composites each full-bleed tile under the mask shapes Android
// and PWA launchers actually apply, so clipping is visible rather than assumed.
const path = require('path');
const sharp = require('sharp');
const { svgTile } = require('./svg.js');

const CELL = 260;
const CAPTION = 18;
const TILE = 216; // 108dp at 2x
const VIEW = CELL - 20;
const HERE = __dirname;

// Squircle (Pixel default), the spec circle, the iOS rounded rect, and an 80%
// safe-zone guide, so every clipping failure mode shows in one sheet.
const MASKS = {
  squircle: (s) => roundRect(s, s * 0.22),
  circle: (s) => {
    const c = s / 2;
    return `M${c},0 A${c},${c} 0 1 0 ${c},${s} A${c},${c} 0 1 0 ${c},0 Z`;
  },
  rounded: (s) => roundRect(s, s * 0.28),
  safe80: (s) => `M${s * 0.1},${s * 0.1} H${s * 0.9} V${s * 0.9} H${s * 0.1} Z`,
  safe66: (s) => `M${s * 0.1944},${s * 0.1944} H${s * 0.8056} V${s * 0.8056} H${s * 0.1944} Z`,
};

function roundRect(s, r) {
  return (
    `M${r},0 H${s - r} A${r},${r} 0 0 1 ${s},${r} V${s - r} ` +
    `A${r},${r} 0 0 1 ${s - r},${s} H${r} A${r},${r} 0 0 1 0,${s - r} V${r} A${r},${r} 0 0 1 ${r},0 Z`
  );
}

async function cell({ mask, fit, caption }) {
  const art = await sharp(Buffer.from(svgTile(fit, '#000000', TILE, '#ffffff'))).png().toBuffer();

  const masked =
    mask === null
      ? art
      : await sharp(art)
          .composite([
            {
              input: Buffer.from(
                `<svg xmlns="http://www.w3.org/2000/svg" width="${TILE}" height="${TILE}"><path fill="#fff" d="${MASKS[mask](TILE)}"/></svg>`,
              ),
              blend: 'dest-in',
            },
          ])
          .png()
          .toBuffer();

  const shown = await sharp(masked).resize(VIEW, VIEW, { kernel: 'nearest' }).png().toBuffer();
  return sharp(
    Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${CELL}" height="${CELL + CAPTION}">` +
        `<rect x="0" y="0" width="${CELL}" height="${CELL}" fill="#8a8a8a"/>` +
        `<image href="data:image/png;base64,${shown.toString('base64')}" x="10" y="10" width="${VIEW}" height="${VIEW}" image-rendering="pixelated"/>` +
        `<rect x="0" y="${CELL}" width="${CELL}" height="${CAPTION}" fill="#000000"/>` +
        `<text x="${CELL / 2}" y="${CELL + 13}" font-family="monospace" font-size="10" text-anchor="middle" fill="#ffffff">${caption}</text>` +
        `</svg>`,
    ),
  )
    .png()
    .toBuffer();
}

(async () => {
  const rows = [
    [
      await cell({ mask: 'squircle', fit: 'adaptiveFg', caption: 'adaptive + squircle' }),
      await cell({ mask: 'circle', fit: 'adaptiveFg', caption: 'adaptive + circle' }),
      await cell({ mask: 'safe80', fit: 'adaptiveFg', caption: 'adaptive vs 80% box' }),
      await cell({ mask: 'safe66', fit: 'adaptiveFg', caption: 'adaptive vs 66dp box' }),
    ],
    [
      await cell({ mask: 'circle', fit: 'maskable', caption: 'maskable + circle' }),
      await cell({ mask: 'squircle', fit: 'maskable', caption: 'maskable + squircle' }),
      await cell({ mask: 'safe80', fit: 'maskable', caption: 'maskable vs 80% box' }),
      await cell({ mask: null, fit: 'icon', caption: 'legacy full-bleed' }),
    ],
  ];

  const strips = [];
  for (const r of rows) {
    strips.push(
      await sharp({ create: { width: r.length * CELL, height: CELL + CAPTION, channels: 4, background: '#000000' } })
        .composite(r.map((buf, i) => ({ input: buf, top: 0, left: i * CELL })))
        .png()
        .toBuffer(),
    );
  }

  await sharp({ create: { width: 4 * CELL, height: 2 * (CELL + CAPTION), channels: 4, background: '#000000' } })
    .composite(strips.map((s, i) => ({ input: s, top: i * (CELL + CAPTION), left: 0 })))
    .png()
    .toFile(path.join(HERE, 'qa.png'));
  console.log('wrote qa.png');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});