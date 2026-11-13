const test = require('node:test');
const assert = require('node:assert');
const {
  serializeComment,
} = require('../src/modules/comments/controller');
const { serialize } = require('../src/modules/comments/comment-store');

const comment = {
  id: '11111111-1111-1111-1111-111111111111',
  content: 'hello',
  createdAt: new Date('2025-06-01T00:00:00Z'),
  user: { firebaseUid: 'firebase-uid-1', displayName: 'Asha', avatarUrl: 'https://img/a.jpg' },
};

test('serializeComment maps author to users/{uid} contract', () => {
  const out = serializeComment(comment, 3);
  assert.strictEqual(out.id, comment.id);
  assert.strictEqual(out.userId, 'firebase-uid-1');
  assert.strictEqual(out.userName, 'Asha');
  assert.strictEqual(out.userImage, 'https://img/a.jpg');
  assert.strictEqual(out.text, 'hello');
  assert.strictEqual(out.createdAt, '2025-06-01T00:00:00.000Z');
  assert.strictEqual(out.replyCount, 3);
});

test('serializeComment falls back name to Unknown and image to null', () => {
  const out = serializeComment(
    { ...comment, user: { firebaseUid: 'f', displayName: null, avatarUrl: null } },
    0,
  );
  assert.strictEqual(out.userName, 'Unknown');
  assert.strictEqual(out.userImage, null);
});

test('comment-store serialize reads the flattened Firestore doc shape', () => {
  const out = serialize(
    { id: 'doc-1', userId: 'firebase-uid-1', userName: 'Asha', userImage: 'https://img/a.jpg', content: 'hello', createdAt: '2025-06-01T00:00:00.000Z' },
    2,
  );
  assert.strictEqual(out.id, 'doc-1');
  assert.strictEqual(out.userId, 'firebase-uid-1');
  assert.strictEqual(out.text, 'hello');
  assert.strictEqual(out.createdAt, '2025-06-01T00:00:00.000Z');
  assert.strictEqual(out.replyCount, 2);
});