/* Soko Vibe — responsive product image system.
   Wraps raw backend URLs into sized, lazy, format-adapted <picture> elements.
   Supports Cloudinary-style transformations and generic width-param CDNs. */
(function () {
  const C = window.SV.components;
  const { icon } = C;

  /* Display widths per size key — must reflect the real rendered width so
     the browser picks a small file instead of the largest candidate. */
  const IMG = {
    base: '',
    defaultSize: 400,
    sizes: { thumb: 200, small: 400, medium: 640, large: 1024 },
    sizesAttr: {
      thumb: '(max-width: 640px) 30vw, 120px',
      small: '(max-width: 640px) 44vw, 200px',
      medium: '(max-width: 640px) 44vw, 220px',
      large: '(max-width: 640px) 96vw, 640px'
    },
    /* Build a resized URL. Cloudinary delivery URLs get a real in-path
       transformation (query params alone do NOT resize on Cloudinary);
       anything else falls back to width/format query params. */
    resize(url, w) {
      if (!url) return '';
      const m = String(url).match(/^(https?:\/\/[^/]+\/[^/]+\/image\/upload\/)(.*)$/);
      if (m) return m[1] + 'w_' + w + ',f_auto,q_auto/' + m[2];
      return url + (url.includes('?') ? '&' : '?') + 'w=' + w + '&fm=webp';
    },
    /* srcset string for a given original URL */
    srcset(url) {
      if (!url) return '';
      const s = ['200', '400', '640', '1024'];
      return s.map((w) => this.resize(url, w) + ' ' + w + 'w').join(', ');
    },
  };

  /* Aspect-ratio container + picture element */
  function img(url, alt, opts) {
    opts = opts || {};
    const size = opts.size || 'medium';
    const w = IMG.sizes[size] || IMG.defaultSize;
    const altText = alt || '';
    const loading = opts.lazy !== false ? 'lazy' : 'eager';
    const cls = opts.class ? opts.class : '';
    const style = opts.style ? opts.style : '';
    const sizesAttr = opts.sizes || IMG.sizesAttr[size] || IMG.sizesAttr.medium;

    /* low-res blur placeholder when a tiny URL is provided */
    let blurAttr = '';
    if (opts.blur) blurAttr = ' style="background-image:url(' + opts.blur + ')"';

    return '<div class="sv-img" style="aspect-ratio:' + (opts.ratio || '1 / 1') + ';overflow:hidden;' + style + '">'
      + '<picture>'
      + '<source type="image/avif" srcset="' + IMG.srcset(url) + '" sizes="' + sizesAttr + '">'
      + '<source type="image/webp" srcset="' + IMG.srcset(url) + '" sizes="' + sizesAttr + '">'
      + '<img src="' + IMG.resize(url, w) + '" '
      + 'srcset="' + IMG.srcset(url) + '" sizes="' + sizesAttr + '" '
      + 'alt="' + esc(altText) + '" loading="' + loading + '" decoding="async" '
      + 'width="' + w + '" height="' + w + '" '
      + 'class="' + cls + '"' + blurAttr
      + ' onerror="this.parentElement.classList.add(\'sv-badimg\');this.remove()">'
      + '</picture>'
      + '</div>';
  }

  /* gallery thumbnail */
  function thumb(url, index, active) {
    if (!url) return '';
    return '<button type="button" class="sv-gallery-thumb' + (active ? ' on' : '') + '" data-gi="' + index + '" aria-label="' + esc(index + 1) + '">'
      + img(url, '', { size: 'thumb', lazy: true, ratio: '1 / 1', class: 'sv-gallery-thumb-img' })
      + '</button>';
  }

  window.SV = window.SV || {};
  window.SV.image = { img: img, thumb: thumb, IMG: IMG };
})();