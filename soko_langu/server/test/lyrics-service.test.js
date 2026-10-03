// Lyrics resolution: choosing the right track and turning plain text into
// something the synced viewer can follow.
//
// The pure helpers are tested directly because the network and the AI gateway
// are the parts that vary; the decision logic is the part that silently picks
// the wrong song, which is worse than showing nothing.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { pickBest, plainToLrc, normalize } = require('../src/modules/music/lyrics-service');

const synced = (ms) => `[00:${String(Math.floor(ms / 1000)).padStart(2, '0')}.00] line ${ms}`;

test('prefers a synced candidate over a plain one', () => {
  const best = pickBest(
    [
      { trackName: 'A', plainLyrics: 'words' },
      { trackName: 'B', syncedLyrics: synced(1000) },
    ],
    { durationMs: 200000 },
  );
  assert.equal(best.trackName, 'B');
});

test('matches on duration before anything else', () => {
  // Same song, three lengths: studio, live and a 10-second preview. Duration
  // comes from the file the user actually has, so it is the only reliable signal.
  const best = pickBest(
    [
      { trackName: 'Live', syncedLyrics: synced(5000), duration: 320 },
      { trackName: 'Preview', syncedLyrics: synced(5000), duration: 30 },
      { trackName: 'Studio', syncedLyrics: synced(5000), duration: 201 },
    ],
    { durationMs: 200000 },
  );
  assert.equal(best.trackName, 'Studio');
});

test('ignores a wildly different duration rather than picking it', () => {
  // A karaoke cover can be the only match. Showing its lyrics to someone holding
  // the real track is worse than showing nothing, and the AI fallback exists for
  // exactly this gap.
  const best = pickBest([{ trackName: 'Cover', syncedLyrics: synced(1000), duration: 400 }], {
    durationMs: 180000,
  });
  assert.equal(best, null);
});

test('falls back to the first usable candidate when duration is unknown', () => {
  const best = pickBest(
    [
      { trackName: 'Only', syncedLyrics: synced(1000) },
    ],
    {},
  );
  assert.equal(best.trackName, 'Only');
});

test('an unusable candidate list yields null', () => {
  assert.equal(pickBest([], { durationMs: 1000 }), null);
  assert.equal(pickBest([{ trackName: 'x' }], { durationMs: 1000 }), null);
  assert.equal(pickBest(null, {}), null);
});

test('plain lyrics become timestamped across the real duration', () => {
  const lrc = plainToLrc('one\ntwo\nthree', 60000);
  const lines = lrc.split('\n');
  assert.equal(lines.length, 3);
  assert.ok(lines[0].startsWith('[00:00.00]'), `first stamp wrong: ${lines[0]}`);
  // 60s / 3 lines = 20s apart.
  assert.ok(lines[1].startsWith('[00:20.00]'), `second stamp wrong: ${lines[1]}`);
  assert.ok(lines[2].startsWith('[00:40.00]'), `third stamp wrong: ${lines[2]}`);
});

test('plain lyrics never run past the end of the track', () => {
  const lrc = plainToLrc('a\nb\nc\nd', 40000);
  const last = lrc.split('\n').pop();
  const m = /^\[(\d{2}):(\d{2})\./.exec(last);
  const seconds = Number(m[1]) * 60 + Number(m[2]);
  assert.ok(seconds <= 40, `last line at ${seconds}s exceeds a 40s track`);
});

test('blank lines and empty input are handled', () => {
  assert.equal(plainToLrc('', 1000), '');
  assert.equal(plainToLrc('   \n\n  ', 1000), '');
  assert.equal(plainToLrc('only line', 60000).split('\n').length, 1);
});

test('an unknown duration still produces a usable timeline', () => {
  const lrc = plainToLrc('a\nb', undefined);
  assert.equal(lrc.split('\n').length, 2);
});

test('normalize folds case and runs of whitespace for cache keys', () => {
  assert.equal(normalize('  Shape  OF   You '), 'shape of you');
  assert.equal(normalize(null), '');
});

test('timestamps keep millisecond precision the parser can read', () => {
  const lrc = plainToLrc('x', 1500);
  assert.match(lrc, /^\[\d{2}:\d{2}\.\d{2}\]/);
});