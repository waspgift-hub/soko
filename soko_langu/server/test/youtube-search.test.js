const { test } = require('node:test');
const assert = require('node:assert/strict');

const { parseYouTubeSearch, searchYouTube } = require('../src/modules/youtube/youtube-service');

const fixture = {
  items: [
    {
      id: { videoId: 'abc123XYZ_-', kind: 'youtube#video' },
      snippet: {
        title: 'Song One',
        channelTitle: 'Channel A',
        publishedAt: '2024-01-01T00:00:00Z',
        thumbnails: { medium: { url: 'https://img/mq.jpg' } },
      },
    },
    {
      id: { kind: 'youtube#channel' },
      snippet: { title: 'A channel, not a video' },
    },
    {
      id: { videoId: 'secondId1234' },
      snippet: { title: '', channelTitle: '', thumbnails: {} },
    },
  ],
};

test('parseYouTubeSearch keeps only videos with the app shape', () => {
  const out = parseYouTubeSearch(fixture);
  assert.equal(out.length, 2);
  assert.deepEqual(out[0], {
    videoId: 'abc123XYZ_-',
    title: 'Song One',
    channel: 'Channel A',
    thumbnail: 'https://img/mq.jpg',
    publishedAt: '2024-01-01T00:00:00Z',
  });
  assert.equal(out[1].thumbnail, '');
});

test('parseYouTubeSearch tolerates garbage bodies', () => {
  assert.deepEqual(parseYouTubeSearch(null), []);
  assert.deepEqual(parseYouTubeSearch({}), []);
  assert.deepEqual(parseYouTubeSearch({ items: null }), []);
});

test('searchYouTube answers 503 when no key is configured', async () => {
  const saved = process.env.YOUTUBE_API_KEY;
  delete process.env.YOUTUBE_API_KEY;
  try {
    await assert.rejects(
      searchYouTube({ q: 'bongo flava', fetchImpl: async () => { throw new Error('must not fetch'); } }),
      (e) => e.status === 503 && e.message === 'YOUTUBE_NOT_CONFIGURED',
    );
  } finally {
    if (saved !== undefined) process.env.YOUTUBE_API_KEY = saved;
  }
});

test('searchYouTube rejects too-short queries before any fetch', async () => {
  const saved = process.env.YOUTUBE_API_KEY;
  process.env.YOUTUBE_API_KEY = 'test-key';
  try {
    await assert.rejects(
      searchYouTube({ q: 'a', fetchImpl: async () => { throw new Error('must not fetch'); } }),
      (e) => e.status === 400,
    );
  } finally {
    if (saved === undefined) delete process.env.YOUTUBE_API_KEY;
    else process.env.YOUTUBE_API_KEY = saved;
  }
});

test('searchYouTube caches per normalized query', async () => {
  const saved = process.env.YOUTUBE_API_KEY;
  process.env.YOUTUBE_API_KEY = 'test-key';
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return { ok: true, json: async () => fixture };
  };
  try {
    const first = await searchYouTube({ q: '  Bongo Flava ', fetchImpl });
    assert.equal(first.cached, false);
    assert.equal(first.items.length, 2);
    const second = await searchYouTube({ q: 'bongo flava', fetchImpl });
    assert.equal(second.cached, true);
    assert.equal(calls, 1);
  } finally {
    if (saved === undefined) delete process.env.YOUTUBE_API_KEY;
    else process.env.YOUTUBE_API_KEY = saved;
  }
});
