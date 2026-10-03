// Shared SVG builder. Every target canvas is `viewBox="0 0 S S"` with the mark
// placed by a transform, because a background rect drawn in viewBox user units
// is not stretched to the viewport by librsvg.
const master = require('./master.json');

/** Transform placing the mark's width at `frac` of an SxS canvas, centred. */
function place(fit, size) {
  const frac = typeof fit === 'number' ? fit : master.fracs[fit];
  if (!frac) throw new Error(`unknown fit: ${fit}`);
  const k = (frac * size) / 1000;
  return {
    frac,
    k,
    tx: (size * (1 - frac)) / 2,
    ty: (size - master.inkH * k) / 2,
  };
}

/** Bare mark (no background), transparent. */
function svgMark(fit, color, size) {
  const { k, tx, ty } = place(fit, size);
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
    `<g transform="translate(${tx.toFixed(3)} ${ty.toFixed(3)}) scale(${k.toFixed(6)})">` +
    `<path fill="${color}" d="${master.pathBase}"/></g></svg>`
  );
}

/**
 * Mark on a solid background. `radius` is a fraction of the canvas for the
 * rounded-square shapes launchers and iOS apply.
 */
function svgTile(fit, color, size, bg, radius = 0) {
  const base = svgMark(fit, color, size);
  if (!bg) return base;
  const r = size * radius;
  const rect =
    radius > 0
      ? `<rect x="0" y="0" width="${size}" height="${size}" rx="${r.toFixed(2)}" fill="${bg}"/>`
      : `<rect x="0" y="0" width="${size}" height="${size}" fill="${bg}"/>`;
  return base.replace('<g transform=', rect + '<g transform=');
}

module.exports = { master, place, svgMark, svgTile };