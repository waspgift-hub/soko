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

// Build the full email message for a 6-digit OTP. Recipient email is included
// as the one personalization because it helps users notice a typo'd address.
function buildOtpEmail({ otp, lang = 'sw', expiresInMinutes = 5, recipientEmail }) {
  const c = otpCopy(lang);
  const intro = c.intro.replace('{{minutes}}', String(expiresInMinutes));
  const expires = c.expires.replace('{{minutes}}', String(expiresInMinutes));
  const footerNote = c.footerNote.replace('{{email}}', recipientEmail || '');

  const html = `<!DOCTYPE html>
<html lang="${lang}" dir="ltr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
  <title>${c.subject}</title>
</head>
<body style="margin:0;padding:0;background-color:#F2F5F3;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F2F5F3;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background-color:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid ${BRAND.border};">

          <tr>
            <td align="center" style="padding:40px 24px 8px 24px;">
              <img src="${LOGO_URL}" width="72" height="72" alt="Soko Vibe" style="border:0;display:block;margin:0 auto;border-radius:50%;">
              <p style="margin:14px 0 0 0;font-size:20px;font-weight:700;color:${BRAND.dark};letter-spacing:0.5px;">Soko Vibe</p>
              <p style="margin:2px 0 0 0;font-size:12px;letter-spacing:2.5px;text-transform:uppercase;color:${BRAND.muted};">Tanzania Online Marketplace</p>
            </td>
          </tr>

          <tr>
            <td align="center" style="padding:28px 24px 6px 24px;">
              <p style="margin:0;font-size:15px;color:${BRAND.muted};">${c.greeting}</p>
              <h1 style="margin:8px 0 0 0;font-size:26px;line-height:1.3;color:${BRAND.text};">${c.heading}</h1>
            </td>
          </tr>

          <tr>
            <td align="center" style="padding:20px 24px;">
              <div style="background-color:${BRAND.soft};border:1px solid ${BRAND.green};border-radius:14px;padding:26px 16px;display:inline-block;min-width:200px;">
                <span style="font-family:'Roboto Mono',Consolas,'Courier New',monospace;font-size:40px;font-weight:700;letter-spacing:12px;color:${BRAND.dark};display:inline-block;padding-left:12px;">${otp}</span>
              </div>
              <p style="margin:14px 0 0 0;font-size:13px;color:${BRAND.muted};">${expires}</p>
            </td>
          </tr>

          <tr>
            <td style="padding:8px 32px 8px 32px;">
              <p style="margin:0;font-size:14px;line-height:1.7;color:${BRAND.text};">${intro}</p>
            </td>
          </tr>

          <tr>
            <td align="center" style="padding:16px 32px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="background-color:${BRAND.green};border-radius:999px;padding:0;">
                    <a href="https://www.sokovibe.co.tz" target="_blank" rel="noopener" style="display:inline-block;padding:13px 34px;font-size:15px;font-weight:600;color:#FFFFFF;text-decoration:none;">${c.ctaLabel}</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="padding:14px 32px 8px 32px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAFBFA;border-radius:10px;border:1px solid ${BRAND.border};">
                <tr>
                  <td style="padding:14px 18px;font-size:13px;line-height:1.6;color:${BRAND.muted};">
                    <strong style="color:${BRAND.text};">${c.securityTitle}</strong><br>
                    ${c.securityBody}
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="padding:20px 32px 8px 32px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td style="border-top:1px solid ${BRAND.border};padding-top:18px;">
                    <p style="margin:0 0 4px 0;font-size:13px;font-weight:700;color:${BRAND.dark};letter-spacing:0.3px;">${c.aboutTitle}</p>
                    <p style="margin:0;font-size:13px;line-height:1.7;color:${BRAND.muted};">${c.aboutBody}</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <tr>
            <td style="padding:12px 32px 36px 32px;">
              <p style="margin:0;font-size:12px;line-height:1.6;color:#9CA3AF;">${footerNote}</p>
            </td>
          </tr>

        </table>

        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;">
          <tr>
            <td align="center" style="padding:18px 16px 8px 16px;font-size:12px;color:${BRAND.muted};">
              <span style="text-transform:uppercase;letter-spacing:1px;font-weight:600;color:#4B5563;">Soko Vibe</span> · Dar es Salaam, Tanzania<br>
              <span style="color:${BRAND.green};"><a href="https://www.sokovibe.co.tz" style="color:${BRAND.green};text-decoration:none;">www.sokovibe.co.tz</a></span> · <a href="mailto:support@sokovibe.co.tz" style="color:${BRAND.green};text-decoration:none;">support@sokovibe.co.tz</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  return { subject: c.subject, html };
}

// Security notification: password was changed. No links, no codes — if the
// recipient did not do this, the mail tells them exactly where to get help.
function buildPasswordChangedEmail({ lang = 'sw', when = null } = {}) {
  const en = lang === 'en';
  const c = en
    ? {
        subject: 'Soko Vibe — Your password was changed',
        heading: 'Password changed',
        intro: `Your Soko Vibe password was changed${when ? ` on ${when}` : ''}. All other devices have been signed out automatically.`,
        securityTitle: 'Wasn\'t you?',
        securityBody: 'Someone with access to your phone or email changed this password. Contact Soko Vibe Support immediately at support@sokovibe.co.tz so we can secure your account.',
      }
    : {
        subject: 'Soko Vibe — Nenosiri lako limebadilishwa',
        heading: 'Nenosiri limebadilishwa',
        intro: `Nenosiri lako la Soko Vibe limebadilishwa${when ? ` mnamo ${when}` : ''}. Vifaa vingine vyote vimetolewa nje kiotomatiki.`,
        securityTitle: 'Si wewe?',
        securityBody: 'Mtu mwenye ufikiaji wa simu au barua pepe yako amebadilisha nenosiri hili. Wasiliana na Msaada wa Soko Vibe mara moja kupitia support@sokovibe.co.tz ili tukulinde akaunti yako.',
      };

  const html = `<!DOCTYPE html>
<html lang="${en ? 'en' : 'sw'}" dir="ltr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="color-scheme" content="light">
  <meta name="supported-color-schemes" content="light">
  <title>${c.subject}</title>
</head>
<body style="margin:0;padding:0;background-color:#F2F5F3;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#F2F5F3;">
    <tr>
      <td align="center" style="padding:32px 16px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background-color:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid ${BRAND.border};">
          <tr>
            <td align="center" style="padding:40px 24px 8px 24px;">
              <img src="${LOGO_URL}" width="72" height="72" alt="Soko Vibe" style="border:0;display:block;margin:0 auto;border-radius:50%;">
              <p style="margin:14px 0 0 0;font-size:20px;font-weight:700;color:${BRAND.dark};letter-spacing:0.5px;">Soko Vibe</p>
              <p style="margin:2px 0 0 0;font-size:12px;letter-spacing:2.5px;text-transform:uppercase;color:${BRAND.muted};">Tanzania Online Marketplace</p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:28px 24px 6px 24px;">
              <h1 style="margin:0;font-size:26px;line-height:1.3;color:${BRAND.text};">${c.heading}</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 8px 32px;">
              <p style="margin:0;font-size:14px;line-height:1.7;color:${BRAND.text};">${c.intro}</p>
            </td>
          </tr>
          <tr>
            <td style="padding:14px 32px 36px 32px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#FAFBFA;border-radius:10px;border:1px solid ${BRAND.border};">
                <tr>
                  <td style="padding:14px 18px;font-size:13px;line-height:1.6;color:${BRAND.muted};">
                    <strong style="color:${BRAND.text};">${c.securityTitle}</strong><br>
                    ${c.securityBody}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;">
          <tr>
            <td align="center" style="padding:18px 16px 8px 16px;font-size:12px;color:${BRAND.muted};">
              <span style="text-transform:uppercase;letter-spacing:1px;font-weight:600;color:#4B5563;">Soko Vibe</span> · Dar es Salaam, Tanzania<br>
              <span style="color:${BRAND.green};"><a href="https://www.sokovibe.co.tz" style="color:${BRAND.green};text-decoration:none;">www.sokovibe.co.tz</a></span> · <a href="mailto:support@sokovibe.co.tz" style="color:${BRAND.green};text-decoration:none;">support@sokovibe.co.tz</a>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  return { subject: c.subject, html };
}

module.exports = { buildOtpEmail, buildPasswordChangedEmail };