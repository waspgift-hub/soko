#!/usr/bin/env node
// send-test-otps.js — triggers a live email OTP and phone (SMS) OTP for the
// e2e test user so the delivery chains (SMTP + Meseji/NotifyAfrica) can be
// confirmed end-to-end.
//
// The deployed API rate-limits OTP sends to 3/15min per IP (otpRequestLimiter),
// so run this from a fresh network if you hit 429 — or wait ~15 minutes.
//
// Usage:
//   node scripts/send-test-otps.js
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const baseUrl = process.env.OTP_BASE_URL || 'https://api.sokovibe.co.tz/api/v1';
const email = process.env.TEST_USER_EMAIL || 'langusoko@gmail.com';
const phone = process.env.TEST_USER_PHONE || '+255719537300';

async function post(path, body) {
  const res = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text };
}

async function main() {
  console.log('Send OTP kwa', email, 'na', phone, '\n');

  const emailRes = await post('/auth/send-email-otp', { email, langCode: 'sw' });
  console.log(`[email-otp] -> ${emailRes.status} ${emailRes.body}`);

  const phoneRes = await post('/auth/send-otp', { phone, langCode: 'sw' });
  console.log(`[sms-otp]   -> ${phoneRes.status} ${phoneRes.body}`);

  console.log('\nAngalia kikasha cha langusoko@gmail.com na SMS kwenye',
    phone, '. OTP zina muda wa dakika 5.');
}

main().catch((e) => {
  console.error('send-test-otps failed:', e.message);
  process.exit(1);
});