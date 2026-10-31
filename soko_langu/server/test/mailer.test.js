const { test } = require('node:test');
const assert = require('node:assert/strict');
const { sendMail } = require('../src/services/mailer');

const originalApiKey = process.env.RESEND_API_KEY;
const originalFrom = process.env.RESEND_FROM;
const originalFetch = global.fetch;

function restoreEnvironment() {
  if (originalApiKey === undefined) delete process.env.RESEND_API_KEY;
  else process.env.RESEND_API_KEY = originalApiKey;
  if (originalFrom === undefined) delete process.env.RESEND_FROM;
  else process.env.RESEND_FROM = originalFrom;
  global.fetch = originalFetch;
}

test('sendMail returns false when Resend configuration is missing', async () => {
  delete process.env.RESEND_API_KEY;
  process.env.RESEND_FROM = 'SokoVibe <no-reply@sokovibe.co.tz>';
  try {
    assert.equal(await sendMail('buyer@example.com', 'Test', '<p>Hello</p>'), false);
  } finally {
    restoreEnvironment();
  }
});

test('sendMail posts the expected payload to Resend', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.RESEND_FROM = 'SokoVibe <no-reply@sokovibe.co.tz>';
  let request;
  global.fetch = async (url, options) => {
    request = { url, options, body: JSON.parse(options.body) };
    return { ok: true, status: 200 };
  };

  try {
    assert.equal(await sendMail('buyer@example.com', 'Welcome', '<p>Karibu</p>'), true);
    assert.equal(request.url, 'https://api.resend.com/emails');
    assert.equal(request.options.method, 'POST');
    assert.equal(request.options.headers.Authorization, 'Bearer re_test_key');
    assert.deepEqual(request.body, {
      from: 'SokoVibe <no-reply@sokovibe.co.tz>',
      to: ['buyer@example.com'],
      subject: 'Welcome',
      html: '<p>Karibu</p>',
    });
  } finally {
    restoreEnvironment();
  }
});

test('sendMail returns false when Resend rejects the request', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.RESEND_FROM = 'SokoVibe <no-reply@sokovibe.co.tz>';
  global.fetch = async () => ({
    ok: false,
    status: 422,
    text: async () => '{"message":"domain is not verified"}',
  });

  try {
    assert.equal(await sendMail('buyer@example.com', 'Welcome', '<p>Karibu</p>'), false);
  } finally {
    restoreEnvironment();
  }
});
