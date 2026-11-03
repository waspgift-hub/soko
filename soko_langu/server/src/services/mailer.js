// Central transactional email service backed by the Resend HTTP API.
// Render provides RESEND_API_KEY and RESEND_FROM as environment variables.
const RESEND_API_URL = 'https://api.resend.com/emails';

async function sendMail(to, subject, html) {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM;

  if (!apiKey || !from) {
    console.error('[MAILER] Resend is not configured (RESEND_API_KEY / RESEND_FROM missing)');
    return false;
  }

  const recipients = Array.isArray(to) ? to : [to];
  if (
    recipients.length === 0 ||
    recipients.some((recipient) => typeof recipient !== 'string' || !recipient.trim()) ||
    typeof subject !== 'string' ||
    !subject.trim() ||
    typeof html !== 'string' ||
    !html.trim()
  ) {
    console.error('[MAILER] Invalid email payload');
    return false;
  }

  try {
    const response = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: recipients,
        subject,
        html,
      }),
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      // Do not log request headers or credentials. Resend's response body is
      // useful for diagnosing rejected sender/domain configuration.
      const details = await response.text().catch(() => '');
      console.error('[MAILER] Resend API rejected email:', response.status, details.slice(0, 300));
      return false;
    }

    return true;
  } catch (error) {
    console.error('[MAILER] Resend request failed:', error.message);
    return false;
  }
}

module.exports = { sendMail };
