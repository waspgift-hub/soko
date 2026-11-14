// Transactional email templates. Every send builds HTML inline-styled for
// Gmail/Outlook image-blocking safety; the only remote asset is the brand
// icon hosted on the CDN-backed landing origin (immutable cache headers).

const BRAND = {
  green: '#40916C',
  dark: '#2D6A4F',
  soft: '#E8F4EE',
  text: '#1F2937',
  muted: '#6B7280',
  border: '#E5E7EB',
};

// Canonical public icon — same asset the landing site uses for og:image and
// the structured-data logo, so email branding matches the web exactly.
const LOGO_URL = 'https://www.sokovibe.co.tz/assets/icon-512.png?v=2';

function otpCopy(lang) {
  if (lang === 'en') {
    return {
      subject: 'Soko Vibe — Your login code',
      greeting: 'Karibu, mpenzi wa Soko Vibe!',
      heading: 'Your verification code',
      intro: 'Use the code below to complete sign-in. It is valid for one use only and expires in {{minutes}} minutes.',
      expires: 'Expires in {{minutes}} minutes · single use',
      securityTitle: 'Didn\'t request this?',
      securityBody: 'Ignore this email. Never share this code — even with someone claiming to be Soko Vibe support.',
      aboutTitle: 'Why Soko Vibe?',
      aboutBody: 'Soko Vibe is Tanzania\'s trusted online marketplace — trade safely with escrow payment, pay by M-Pesa, Tigo Pesa, Airtel Money or HaloPesa, and confirm delivery with OTP before your money is released.',
      footerNote: 'This one-time transactional email was sent to {{email}}.',
      ctaLabel: 'Open Soko Vibe',
    };
  }
  return {
    subject: 'Soko Vibe — Namba yako ya kuingia',
    greeting: 'Karibu kwenye Soko Vibe!',
    heading: 'Namba yako ya uthibitisho',
    intro: 'Ingiza namba hapa chini kukamilisha kuingia. Inatumika mara moja tu na inaisha kwa dakika {{minutes}}.',
    expires: 'Muda: dakika {{minutes}} · kutumika mara moja tu',
    securityTitle: 'Hukuitaka hii?',
    securityBody: 'Puuza barua hii. Kamwe usimshirikie mtu mwingine namba hii — hata anajitambulisha kama msaada wa Soko Vibe.',
    aboutTitle: 'Kuhusu Soko Vibe',
    aboutBody: 'Soko Vibe ni soko la Tanzania linalojenga uaminifu kwenye mtandao — nunua na uza kwa usalama: malipo ya escrow, lipa kwa M-Pesa, Tigo Pesa, Airtel Money au HaloPesa, na thibitisha usafirishaji kwa OTP kabla fedha zako kutolewa.',
    footerNote: 'Barua hii ya moja kwa moja ilitumwa kwa {{email}}.',
    ctaLabel: 'Fungua Soko Vibe',
  };
}

// Build OTP email payload for the One UI mailer. Content is rendered by
// mailer.wrapEmailHtml(action='otp') so all transactional emails share one shell.
function buildOtpEmail({ otp, lang = 'sw', expiresInMinutes = 5 }) {
  const c = otpCopy(lang);
  return {
    subject: c.subject,
    html: '',
    action: 'otp',
    context: { otp, lang, expiresInMinutes },
  };
}

// Security notification: password changed. Rendered by the One UI mailer shell.
function buildPasswordChangedEmail({ lang = 'sw', when = null } = {}) {
  const en = lang === 'en';
  const subject = en
    ? 'Soko Vibe — Your password was changed'
    : 'Soko Vibe — Nenosiri lako limebadilishwa';
  return {
    subject,
    html: '',
    action: 'password-changed',
    context: { lang, when },
  };
}
module.exports = { buildOtpEmail, buildPasswordChangedEmail };