const test = require('node:test');
const assert = require('node:assert');

const {
  serialize,
  extractMentionHandles,
  clampLimit,
  MAX_CONTENT,
} = require('../src/modules/comments/comment-store');
const { notifyId, truncate } = require('../src/modules/comments/comment-notifications');

test('serialize exposes the Instagram-style comment shape', () => {
  const out = serialize(
    {
      id: 'c1',
      userId: 'u1',
      userName: 'Asha',
      username: 'asha',
      userImage: 'https://img/a.jpg',
      content: 'bei gani?',
      createdAt: '2026-01-01T10:00:00.000Z',
      editedAt: '2026-01-01T10:05:00.000Z',
      pinned: true,
      likeCount: 4,
      likedByMe: true,
      parentId: null,
      mentions: ['u2'],
    },
    3,
  );

  assert.strictEqual(out.id, 'c1');
  assert.strictEqual(out.text, 'bei gani?');
  assert.strictEqual(out.replyCount, 3);
  assert.strictEqual(out.likeCount, 4);
  assert.strictEqual(out.likedByMe, true);
  assert.strictEqual(out.pinned, true);
  assert.strictEqual(out.editedAt, '2026-01-01T10:05:00.000Z');
  assert.strictEqual(out.deleted, false);
  assert.deepStrictEqual(out.mentions, ['u2']);
});

test('serialize renders a tombstone without exposing deleted text', () => {
  const out = serialize(
    {
      id: 'c2',
      userId: 'u1',
      userName: 'Asha',
      content: 'secret',
      deletedAt: '2026-01-02T00:00:00.000Z',
      createdAt: '2026-01-01T00:00:00.000Z',
    },
    0,
  );
  assert.strictEqual(out.deleted, true);
  assert.strictEqual(out.text, '');
});

test('extractMentionHandles finds unique handles and ignores emails', () => {
  const handles = extractMentionHandles('Habari @Asha na @juma_d. Barua: a@b.com @asha');
  assert.deepStrictEqual(handles.sort(), ['asha', 'juma_d']);
});

test('extractMentionHandles caps the number of mentions', () => {
  const text = Array.from({ length: 20 }, (_, i) => `@user${i}`).join(' ');
  assert.strictEqual(extractMentionHandles(text).length, 10);
});

test('extractMentionHandles requires a word boundary before @', () => {
  assert.deepStrictEqual(extractMentionHandles('email a@b.com'), []);
});

test('clampLimit bounds page size to the server maximum', () => {
  assert.strictEqual(clampLimit(0), 20);
  assert.strictEqual(clampLimit(-5), 20);
  assert.strictEqual(clampLimit(9999), 50);
  assert.strictEqual(clampLimit('7'), 7);
});

test('MAX_CONTENT is the documented 2000 character ceiling', () => {
  assert.strictEqual(MAX_CONTENT, 2000);
});

test('notifyId is deterministic and safe as a Firestore document id', () => {
  const a = notifyId(['comment', 'abc/def', 'seller']);
  const b = notifyId(['comment', 'abc/def', 'seller']);
  assert.strictEqual(a, b);
  assert.ok(/^[a-zA-Z0-9_-]+$/.test(a));
  assert.ok(a.length <= 200);
});

test('truncate keeps short text and ellipsizes long text', () => {
  assert.strictEqual(truncate('hello', 10), 'hello');
  assert.strictEqual(truncate('hello world', 5), 'hello…');
  assert.strictEqual(truncate('  spaced   out  ', 30), 'spaced out');
});
