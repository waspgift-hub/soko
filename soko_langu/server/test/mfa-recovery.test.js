const test = require('node:test');
const assert = require('node:assert/strict');
const { hashCode, normalizeCode, generateCode, CODE_RE } = require('../src/modules/auth/mfa-recovery');

test('recovery codes are normalized and stored only as hashes', () => {
  assert.equal(normalizeCode(' abcd-ef23 '), 'ABCD-EF23');
  assert.equal(hashCode('abcd-ef23'), hashCode('ABCD-EF23'));
  assert.notEqual(hashCode('ABCD-EF23'), 'ABCD-EF23');
  assert.equal(hashCode('ABCD-EF23').length, 64);
});

test('generated recovery codes match the single-use format', () => {
  for (let i = 0; i < 20; i += 1) {
    assert.match(generateCode(), CODE_RE);
  }
});
