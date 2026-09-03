// SMTP mailer for transactional email (OTP codes). Uses Gmail/app-password
// style env config, same as the legacy server.
const nodemailer = require('nodemailer');

let transporter = null;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || 'smtp.gmail.com',
      port: parseInt(process.env.SMTP_PORT || '587', 10),
      secure: process.env.SMTP_SECURE === 'true',
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
  }
  return transporter;
}

async function sendMail(to, subject, html) {
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) {
    console.error('[MAILER] SMTP not configured');
    return false;
  }
  try {
    await getTransporter().sendMail({
      from: process.env.SMTP_FROM || 'Soko Vibe <waspgift@gmail.com>',
      to,
      subject,
      html,
    });
    return true;
  } catch (e) {
    console.error('[MAILER] send failed:', e.message);
    return false;
  }
}

module.exports = { sendMail };
