// Traces the Soko Vibe "SV" monogram from the supplied 1920px PNG into a
// normalised SVG path. Consumers rasterise it with svgFor() from ./svg.js.
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const potrace = require('potrace');
const svgpath = require('svgpath');

const HERE = __dirname;
const SRC = process.argv[2] || path.join(HERE, 'src', 'soko_vibe_mark_1920.png');
const OUT = path.join(HERE, 'master.json');

// Fraction of the canvas the mark's WIDTH should occupy, per target. Each value
// was picked by rendering the result at its true on-device pixel size and
// checking that the S counters and the diagonal gap between S and V survive.
const FIT = {
  // Launcher / in-app / PWA icons: matches the 56% mark width already shipped,
  // so the home-screen icon does not change apparent size.
  icon: 0.56,
  // Maskable PWA: the spec guarantees only the inner 80%, so the mark stays
  // clear of a circular crop.
  maskable: 0.52,
  // Adaptive launcher foreground: Android guarantees the central 72/108 dp, and
  // the mark's bounding box fits inside it.
  adaptiveFg: 0.55,
  // Notification small icon: 24dp canvas. Wider closes up the S counters at
  // true render size.
  notification: 0.8,
  // Favicons below 32px lose the thin diagonal gap; a wider mark buys pixels.
  faviconSmall: 0.72,
  favicon: 0.58,
  appleTouch: 0.6,
};

const WORK = 1200;

function alphaBinarised(file, size) {
  // Potrace reads luminance, so alpha is flattened to grey: ink light, paper
  // black.
  return sharp(file)
    .resize(size, size, { fit: 'fill' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true })
    .then(({ data, info }) => {
      const out = Buffer.alloc(info.width * info.height);
      for (let i = 3, p = 0; p < out.length; p++, i += info.channels) out[p] = data[i];
      return { out, width: info.width, height: info.height };
    });
}

async function main() {
  const { out, width, height } = await alphaBinarised(SRC, WORK);
  const rawPath = path.join(HERE, '.work.png');
  await sharp(out, { raw: { width, height, channels: 1 } }).png({ colors: 256 }).toFile(rawPath);

  const svg = await new Promise((resolve, reject) => {
    potrace.trace(
      rawPath,
      {
        threshold: 128,
        // Ink is the LIGHT side of the threshold (alpha flattened to grey), so
        // the light side must become the shape.
        blackOnWhite: false,
        turnPolicy: potrace.Potrace.TURNPOLICY_MINORITY,
        turdSize: 4,
        alphaMax: 1.0,
        optCurve: true,
        optTolerance: 0.12, // tight curves: the diagonal gap is the detail that matters
        color: '#ffffff',
      },
      (err, s) => (err ? reject(err) : resolve(s)),
    );
  });

  // `background` is deliberately omitted: setting it makes potrace emit a
  // full-canvas <rect> that would otherwise be picked up as the shape.
  const d = (svg.match(/ d="([^"]+)"/g) || [])
    .map((s) => s.slice(4, -1))
    .reduce((a, b) => (b.length > a.length ? b : a), '');
  if (!d) throw new Error('no path data in potrace output');

  // Measure the real ink extent by rasterising the trace on a transparent
  // canvas: potrace's control points can sit outside the drawn curve, so a
  // path-only bbox would over-estimate and shrink the fitted mark.
  const probe = await sharp(
    Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><path fill="#fff" d="${d}"/></svg>`,
    ),
  )
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const b = { x0: width, y0: height, x1: -1, y1: -1 };
  for (let y = 0; y < probe.info.height; y++) {
    for (let x = 0; x < probe.info.width; x++) {
      if (probe.data[(y * probe.info.width + x) * probe.info.channels + 3] > 8) {
        if (x < b.x0) b.x0 = x;
        if (x > b.x1) b.x1 = x;
        if (y < b.y0) b.y0 = y;
        if (y > b.y1) b.y1 = y;
      }
    }
  }
  if (b.x1 < 0) throw new Error('trace produced no ink');
  const box = { x: b.x0, y: b.y0, width: b.x1 - b.x0 + 1, height: b.y1 - b.y0 + 1 };

  // The source mark measures 1305x1073; a wildly different aspect means the
  // trace picked up the background instead of the glyph.
  const inkAspect = box.width / box.height;
  if (inkAspect < 1.1 || inkAspect > 1.35) {
    throw new Error(`unexpected ink aspect ${inkAspect.toFixed(3)} - trace is wrong`);
  }

  // Normalise so the mark spans x 0..1000, y 0..inkH with no rotation.
  const scale = 1000 / box.width;
  const pathBase = svgpath(d)
    .translate(-box.x, -box.y)
    .scale(scale)
    .abs()
    .round(2)
    .toString();
  const inkH = box.height * scale;

  const meta = {
    source: SRC,
    inkAspect: +inkAspect.toFixed(4),
    inkH: +inkH.toFixed(2),
    subpaths: (pathBase.match(/M/g) || []).length,
    fracs: FIT,
    pathBase,
  };
  fs.writeFileSync(OUT, JSON.stringify(meta, null, 2));
  console.log(`ink aspect ${meta.inkAspect} | inkH ${meta.inkH} | subpaths ${meta.subpaths} | ${pathBase.length} chars`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});