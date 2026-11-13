const test = require('node:test');
const assert = require('node:assert');
const {
  serializeSelfProfile,
} = require('../src/modules/users/controller');
const { applyProfileUpdate } = require('../src/services/account-store');

function baseUser(overrides = {}) {
  return {
    id: 'uuid-user-1',
    firebaseUid: 'firebase-uid-1',
    email: 'a@b.c',
    phone: '255712000000',
    displayName: 'Asha',
    username: 'asha',
    bio: null,
    avatarUrl: null,
    preferredLanguage: 'sw',
    preferredCurrency: 'TZS',
    role: 'buyer',
    accountStatus: 'active',
    metadata: {},
    createdAt: new Date('2025-01-01T00:00:00Z'),
    updatedAt: new Date('2025-01-02T00:00:00Z'),
    ...overrides,
  };
}

test('serializeSelfProfile maps columns + metadata into users/{uid} shape', () => {
  const user = baseUser({
    avatarUrl: 'https://img/x.jpg',
    metadata: {
      profile: {
        location: 'Dar es Salaam',
        mood: 'happy',
        latitude: -6.8,
        longitude: 39.2,
        paymentNumbers: { 'M-PESA': '255712000000' },
        shopBanner: 'https://img/banner.jpg',
        shopBannerColor: '#fff',
        shopAccentColor: '#000',
        gender: 'female',
        dateOfBirth: '1990-01-01',
      },
      lastActive: '2025-01-03T10:00:00.000Z',
    },
  });
  const out = serializeSelfProfile(user, true, new Date('2025-01-03T10:00:00Z'));
  assert.strictEqual(out.id, 'firebase-uid-1');
  assert.strictEqual(out.displayName, 'Asha');
  assert.strictEqual(out.profileImage, 'https://img/x.jpg');
  assert.strictEqual(out.location, 'Dar es Salaam');
  assert.strictEqual(out.mood, 'happy');
  assert.strictEqual(out.latitude, -6.8);
  assert.strictEqual(out.longitude, 39.2);
  assert.deepStrictEqual(out.paymentNumbers, { 'M-PESA': '255712000000' });
  assert.strictEqual(out.shopBanner, 'https://img/banner.jpg');
  assert.deepStrictEqual(out.kyc, { approved: true });
  assert.strictEqual(out.gender, 'female');
  assert.strictEqual(out.dateOfBirth, '1990-01-01');
  assert.strictEqual(out.lastActive, '2025-01-03T10:00:00.000Z');
  assert.strictEqual(out.langCode, 'sw');
});

test('serializeSelfProfile hides kyc when unapproved', () => {
  const out = serializeSelfProfile(baseUser(), false, null);
  assert.deepStrictEqual(out.kyc, { approved: false });
  assert.strictEqual(out.lastActive, null);
});

test('applyProfileUpdate splits columns vs metadata.profile and drops unknowns', () => {
  const user = baseUser({ metadata: { profile: { location: 'Old' } } });
  const { col, meta } = applyProfileUpdate(user, {
    displayName: 'Zawadi',
    username: 'zawadi',
    profileImage: 'https://img/new.jpg',
    shopBanner: 'https://img/banner2.jpg',
    location: 'Arusha',
    gender: 'female',
    nukeMe: 'should be dropped',
  });
  assert.deepStrictEqual(col, {
    displayName: 'Zawadi',
    username: 'zawadi',
    avatarUrl: 'https://img/new.jpg',
  });
  assert.deepStrictEqual(meta.profile, {
    location: 'Arusha',
    gender: 'female',
    shopBanner: 'https://img/banner2.jpg',
  });
});

test('applyProfileUpdate maps empty strings to null for columns', () => {
  const user = baseUser();
  const { col, meta } = applyProfileUpdate(user, {
    displayName: '',
    phone: '  ',
    location: '',
  });
  assert.strictEqual(col.displayName, null);
  assert.strictEqual(col.phone, null);
  assert.strictEqual(meta.profile.location, '');
});

test('applyProfileUpdate merges over existing profile meta without clobbering', () => {
  const user = baseUser({ metadata: { profile: { mood: 'calm', paymentNumbers: { x: '1' } } } });
  const { meta } = applyProfileUpdate(user, { mood: 'great' });
  assert.deepStrictEqual(meta.profile, { mood: 'great', paymentNumbers: { x: '1' } });
});
