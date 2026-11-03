'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizePhone,
  hmacPhone,
} = require('../src/modules/users/contact-discovery');

test('normalizes Tanzanian phone numbers to 255…', () => {
  assert.equal(normalizePhone('0712345678'), '255712345678');
  assert.equal(normalizePhone('+255 712 345 678'), '255712345678');
  assert.equal(normalizePhone('712345678'), '255712345678');
});

test('HMAC is keyed and not a plain phone hash', () => {
  const a = hmacPhone('0712345678', 'secret-a');
  const b = hmacPhone('0712345678', 'secret-b');
  const c = hmacPhone('+255712345678', 'secret-a');
  assert.equal(a.length, 64);
  assert.notEqual(a, b);
  assert.equal(a, c);
  assert.notEqual(a, normalizePhone('0712345678'));
});

test('matchPhones returns 503 when HMAC secret is missing', async () => {
  const { matchPhones } = require('../src/modules/users/contact-discovery');
  await assert.rejects(
    () => matchPhones('self', ['0712345678'], { secret: '' }),
    (err) => err.status === 503 && err.message === 'CONTACT_DISCOVERY_UNCONFIGURED',
  );
});

test('matchPhones looks up HMAC index and excludes self', async () => {
  const { matchPhones, hmacPhone } = require('../src/modules/users/contact-discovery');
  const secret = 'staging-hmac-secret';
  const expectedHash = hmacPhone('0712345678', secret);
  const db = {
    collection(name) {
      assert.equal(name, 'contact_hash_index');
      return {
        doc(hash) {
          return {
            collection(usersCol) {
              assert.equal(usersCol, 'users');
              return {
                limit() {
                  return {
                    async get() {
                      if (hash !== expectedHash) return { docs: [] };
                      return { docs: [{ id: 'self' }, { id: 'friend-1' }] };
                    },
                  };
                },
              };
            },
          };
        },
      };
    },
  };
  const out = await matchPhones('self', ['0712 345 678', '0712345678'], { secret, db });
  assert.deepEqual(out.matches, ['friend-1']);
});
