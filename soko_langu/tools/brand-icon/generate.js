// Writes every icon artefact from the traced master.
//
// Conventions (see README.md for the full table):
//   - Native launcher + in-app logo: WHITE background, BLACK SV mark, so the
//     home-screen icon keeps the apparent size already shipped.
//   - Notification, PWA and website: BLACK background, WHITE SV mark.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { master, place, svgMark, svgTile } = require('./svg.js');

const APP = path.resolve(__dirname, '..', '..');
const BLACK = '#000000';
const WHITE = '#ffffff';

const written = [];
const write = async (rel, buf) => {
  const dest = path.join(APP, rel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, buf);
  written.push(rel);
};

const png = (svg, size, { stripAlpha = false, alphaBg = WHITE } = {}) =>
  sharp(Buffer.from(svg))
    .resize(size, size)
    .png({ compressionLevel: 9, palette: size <= 64 })
    .toBuffer()
    .then((buf) => (stripAlpha ? flattenOpaque(buf, alphaBg) : buf));

function flattenOpaque(buf, bg) {
  return sharp(buf)
    .flatten({ background: bg })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toBuffer();
}

/* ------------------------------------------------------------------ vectors */

// Android VectorDrawable. The transform is expressed as a <group> because
// VectorDrawable has no viewBox crop: it scales, then translates, matching SVG's
// `transform="translate() scale()"` order.
function vectorDrawable({ viewport, fit, fill }) {
  const { k, tx, ty } = place(fit, viewport);
  const n = (v) => +v.toFixed(5);
  return (
    `<vector xmlns:android="http://schemas.android.com/apk/res/android"\n` +
    `    android:width="${viewport}dp"\n` +
    `    android:height="${viewport}dp"\n` +
    `    android:viewportWidth="${viewport}"\n` +
    `    android:viewportHeight="${viewport}">\n` +
    `    <group\n` +
    `        android:scaleX="${n(k)}"\n` +
    `        android:scaleY="${n(k)}"\n` +
    `        android:translateX="${n(tx)}"\n` +
    `        android:translateY="${n(ty)}">\n` +
    `        <path\n` +
    `            android:fillColor="${fill}"\n` +
    `            android:pathData="${master.pathBase}" />\n` +
    `    </group>\n` +
    `</vector>\n`
  );
}

/* ------------------------------------------------------------------- assets */

async function main() {
  const RES = 'android/app/src/main/res';

  // Flutter asset sources.
  await write('assets/icons/app_icon_full.png', await png(svgTile('icon', BLACK, 1024, WHITE)));
  await write('assets/app_icon.png', await png(svgTile('icon', BLACK, 512, WHITE)));
  // Raster reference for the adaptive layers. The adaptive icon itself is built
  // from the vector drawables below, so these are not shipped in any resource
  // set - they exist so the geometry can be inspected without a build.
  await write('assets/icons/ic_foreground.png', await png(svgMark('adaptiveFg', BLACK, 1024)));
  await write('assets/icons/ic_monochrome.png', await png(svgMark('adaptiveFg', BLACK, 1024)));

  // Android vector resources.
  // Android discards notification icon colour and uses only the alpha, so this
  // is a white silhouette by construction.
  await write(`${RES}/drawable/ic_notification.xml`, vectorDrawable({ viewport: 24, fit: 'notification', fill: '#FFFFFFFF' }));
  await write(`${RES}/drawable/ic_launcher_foreground.xml`, vectorDrawable({ viewport: 108, fit: 'adaptiveFg', fill: '#FF000000' }));
  await write(`${RES}/drawable/ic_launcher_monochrome.xml`, vectorDrawable({ viewport: 108, fit: 'adaptiveFg', fill: '#FF000000' }));

  const adaptive = () =>
    `<?xml version="1.0" encoding="utf-8"?>\n` +
    `<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n` +
    `    <background android:drawable="@color/ic_launcher_background" />\n` +
    `    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n` +
    `    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n` +
    `</adaptive-icon>\n`;
  await write(`${RES}/mipmap-anydpi-v26/ic_launcher.xml`, adaptive());
  await write(`${RES}/mipmap-anydpi-v26/ic_launcher_round.xml`, adaptive());

  // Android splash mark. launch_background.xml centres this bitmap at its
  // intrinsic size (96dp), so a single density-less 96px file gets upscaled 3x
  // and looks blurry on xxhdpi+. One bucket per density keeps the on-screen
  // size identical and makes the pixels crisp.
  const SPLASH_DP = 96;
  for (const [bucket, mult] of [['', 1], ['-mdpi', 1], ['-hdpi', 1.5], ['-xhdpi', 2], ['-xxhdpi', 3], ['-xxxhdpi', 4]]) {
    const px = Math.round(SPLASH_DP * mult);
    await write(`${RES}/drawable${bucket}/launch_image.png`, await png(svgTile('icon', BLACK, px, WHITE), px));
  }
  // Keep the pre-API-21 copy in step; the density buckets above win on API 21+.
  await write(`${RES}/drawable-v21/launch_image.png`, await png(svgTile('icon', BLACK, SPLASH_DP, WHITE), SPLASH_DP));

  // Flutter web / PWA: black tile, white mark (matches manifest theme #000000).
  await write('web/favicon-16x16.png', await png(svgTile('faviconSmall', WHITE, 16, BLACK)));
  await write('web/favicon-32x32.png', await png(svgTile('favicon', WHITE, 32, BLACK)));
  await write('web/favicon.png', await png(svgTile('icon', WHITE, 512, BLACK)));
  // iOS applies its own rounded mask and treats any alpha as a transparency
  // mask, so this must be a fully opaque square.
  await write(
    'web/apple-touch-icon.png',
    await png(svgTile('appleTouch', WHITE, 180, BLACK), 180, { stripAlpha: true, alphaBg: BLACK }),
  );
  await write('web/icons/Icon-192.png', await png(svgTile('icon', WHITE, 192, BLACK)));
  await write('web/icons/Icon-512.png', await png(svgTile('icon', WHITE, 512, BLACK)));
  await write('web/icons/Icon-maskable-192.png', await png(svgTile('maskable', WHITE, 192, BLACK)));
  await write('web/icons/Icon-maskable-512.png', await png(svgTile('maskable', WHITE, 512, BLACK)));
  await write('web/favicon.svg', svgTile('icon', WHITE, 512, BLACK, 0.22));

  // favicon.ico packs 16/32/48; small sizes get the widened mark. Browsers show
  // favicons unmasked, so these stay square.
  const ico = [
    { size: 16, fit: 'faviconSmall' },
    { size: 32, fit: 'favicon' },
    { size: 48, fit: 'favicon' },
  ];
  const icoSizes = [];
  let offset = 6 + 16 * ico.length;
  for (const e of ico) {
    const data = await png(svgTile(e.fit, WHITE, e.size, BLACK), e.size);
    icoSizes.push({ ...e, data, offset });
    offset += data.length;
  }
  await write('web/favicon.ico', buildIco(icoSizes));

  // Marketing site + PWA files served from hosting/.
  await write('hosting/favicon.svg', svgTile('icon', WHITE, 512, BLACK, 0.22));
  await write('hosting/favicon.ico', buildIco(icoSizes));
  await write(
    'hosting/apple-touch-icon.png',
    await png(svgTile('appleTouch', WHITE, 180, BLACK), 180, { stripAlpha: true, alphaBg: BLACK }),
  );
  await write('hosting/favicon-16x16.png', await png(svgTile('faviconSmall', WHITE, 16, BLACK)));
  await write('hosting/favicon-32x32.png', await png(svgTile('favicon', WHITE, 32, BLACK)));

  console.log(`wrote ${written.length} files:`);
  for (const w of written) console.log('  ' + w);
}

/** Minimal ICO container (PNG-compressed entries), as browsers and Windows expect. */
function buildIco(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(entries.length, 4);

  const dir = Buffer.alloc(16 * entries.length);
  entries.forEach((e, i) => {
    const o = i * 16;
    dir[o] = e.size >= 256 ? 0 : e.size; // 0 means 256
    dir[o + 1] = e.size >= 256 ? 0 : e.size;
    dir[o + 2] = 0; // palette
    dir[o + 3] = 0; // reserved
    dir.writeUInt16LE(1, o + 4); // colour planes
    dir.writeUInt16LE(32, o + 6); // bits per pixel
    dir.writeUInt32LE(e.data.length, o + 8);
    dir.writeUInt32LE(e.offset, o + 12);
  });

  return Buffer.concat([header, dir, ...entries.map((e) => e.data)]);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});