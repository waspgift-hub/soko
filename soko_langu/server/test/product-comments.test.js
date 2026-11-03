const test = require('node:test');
const assert = require('node:assert');
const {
  serializeComment,
  resolveProduct,
} = require('../src/modules/comments/controller');

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

test('resolveProduct only uses the id arm for uuid-shaped ids', async () => {
  const calls = [];
  const prisma = {
    product: {
      findFirst: async (args) => {
        calls.push(args);
        return null;
      },
    },
  };
  await resolveProduct(prisma, '4db87817-7232-48ac-9420-8466eb5f406c');
  assert.strictEqual(calls.length, 2);
  assert.ok(calls[0].where.id, 'expected an id query for the uuid');
  assert.strictEqual(calls[1].where.snapshot.path[0], 'legacyId');

  calls.length = 0;
  await resolveProduct(prisma, 'legacy-opaque-id-12345');
  assert.strictEqual(calls.length, 1);
  assert.deepStrictEqual(calls[0].where.snapshot, {
    path: ['legacyId'],
    equals: 'legacy-opaque-id-12345',
  });
});