/* Soko Vibe — responsive product image system.
   Wraps raw backend URLs into sized, lazy, format-adapted <picture> elements.
   Supports Cloudinary-style transformations and generic width-param CDNs. */
(function () {
  const C = window.SV.components;
  const { icon } = C;

  /* CDN transformation config. Adjust BASE to the real image host. */
  const IMG = {
    base: '',                       /* e.g. 'https://cdn.sokovibe.co.tz' */
    defaultSize: 400,
    sizes: { thumb: 200, small: 400, medium: 640, large: 1024 },
    /* Build a resized URL. Most CDNs accept ?w=400 or /w_400/. */
    resize(url, w) {
      if (!url) return '';
      if (!this.base) return url + (url.includes('?') ? '&' : '?') + 'w=' + w + '&fm=webp';
      return this.base + url + '?w=' + w + '&fm=webp';
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

    /* low-res blur placeholder when a tiny URL is provided */
    let blurAttr = '';
    if (opts.blur) blurAttr = ' style="background-image:url(' + opts.blur + ')"';

    return '<div class="sv-img" style="aspect-ratio:' + (opts.ratio || '1 / 1') + ';overflow:hidden;' + style + '">'
      + '<picture>'
      + '<source type="image/avif" srcset="' + IMG.srcset(url) + '" sizes="(max-width: 640px) 100vw, ' + w + 'px">'
      + '<source type="image/webp" srcset="' + IMG.srcset(url) + '" sizes="(max-width: 640px) 100vw, ' + w + 'px">'
      + '<img src="' + IMG.resize(url, w) + '" '
      + 'srcset="' + IMG.srcset(url) + '" sizes="(max-width: 640px) 100vw, ' + w + 'px" '
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